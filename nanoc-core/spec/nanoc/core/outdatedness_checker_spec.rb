# frozen_string_literal: true

describe Nanoc::Core::OutdatednessChecker do
  let(:outdatedness_checker) do
    described_class.new(
      site: site,
      checksum_store: checksum_store,
      checksums: checksums,
      dependency_store: dependency_store,
      action_sequence_store: action_sequence_store,
      action_sequences: action_sequences,
      reps: reps,
    )
  end

  let(:checksum_store) { double(:checksum_store) }

  let(:checksums) do
    checksums = {}

    [items, layouts].each do |documents|
      documents.each do |document|
        checksums[[document.reference, :content]] =
          Nanoc::Core::Checksummer.calc_for_content_of(document)
        checksums[[document.reference, :each_attribute]] =
          Nanoc::Core::Checksummer.calc_for_each_attribute_of(document)
      end
    end

    [items, layouts, code_snippets].each do |objs|
      objs.each do |obj|
        checksums[obj.reference] =
          Nanoc::Core::Checksummer.calc(obj)
      end
    end

    checksums[config.reference] =
      Nanoc::Core::Checksummer.calc(config)
    checksums[[config.reference, :each_attribute]] =
      Nanoc::Core::Checksummer.calc_for_each_attribute_of(config)

    Nanoc::Core::ChecksumCollection.new(checksums)
  end

  let(:dependency_store) do
    Nanoc::Core::DependencyStore.new(items, layouts, config)
  end

  let(:items) { Nanoc::Core::ItemCollection.new(config, [item]) }
  let(:layouts) { Nanoc::Core::LayoutCollection.new(config) }

  let(:code_snippets) { [] }

  let(:site) do
    Nanoc::Core::Site.new(
      config: config,
      code_snippets: code_snippets,
      data_source: Nanoc::Core::InMemoryDataSource.new(items, layouts),
    )
  end

  let(:action_sequence_store) do
    Nanoc::Core::ActionSequenceStore.new(config: config)
  end

  let(:old_action_sequence_for_item_rep) do
    Nanoc::Core::ActionSequenceBuilder.build(item_rep) do |b|
      b.add_filter(:erb, {})
    end
  end

  let(:new_action_sequence_for_item_rep) { old_action_sequence_for_item_rep }

  let(:action_sequences) do
    { item_rep => new_action_sequence_for_item_rep }
  end

  let(:reps) do
    Nanoc::Core::ItemRepRepo.new
  end

  let(:item_rep) { Nanoc::Core::ItemRep.new(item, :default) }
  let(:item) { Nanoc::Core::Item.new('stuff', {}, '/foo.md') }

  before do
    reps << item_rep
    action_sequence_store[item_rep] = old_action_sequence_for_item_rep.serialize
  end

  describe 'basic outdatedness reasons' do
    subject { outdatedness_checker.send(:basic).outdatedness_status_for(obj).reasons.first }

    let(:checksum_store) { Nanoc::Core::ChecksumStore.new(config: config, objects: items.to_a + layouts.to_a) }

    let(:config) { Nanoc::Core::Configuration.new(dir: Dir.getwd).with_defaults }

    before do
      checksum_store.add(item)

      allow(site).to receive(:code_snippets).and_return([])
      allow(site).to receive(:config).and_return(config)
    end

    context 'with item' do
      let(:obj) { item }

      context 'action sequence differs' do
        let(:new_action_sequence_for_item_rep) do
          Nanoc::Core::ActionSequenceBuilder.build(item_rep) do |b|
            b.add_filter(:super_erb, {})
          end
        end

        it 'is outdated due to rule differences' do
          expect(subject).to eql(Nanoc::Core::OutdatednessReasons::RulesModified)
        end
      end

      # …
    end

    context 'with item rep' do
      let(:obj) { item_rep }

      context 'action sequence differs' do
        let(:new_action_sequence_for_item_rep) do
          Nanoc::Core::ActionSequenceBuilder.build(item_rep) do |b|
            b.add_filter(:super_erb, {})
          end
        end

        it 'is outdated due to rule differences' do
          expect(subject).to eql(Nanoc::Core::OutdatednessReasons::RulesModified)
        end
      end

      # …
    end

    context 'with layout' do
      # …
    end

    context 'with item collection' do
      let(:obj) { items }

      context 'no new items' do
        it { is_expected.to be_nil }
      end

      context 'new items' do
        before do
          dependency_store.store

          new_item = Nanoc::Core::Item.new('stuff', {}, '/newblahz.md')
          dependency_store.items = Nanoc::Core::ItemCollection.new(config, [item, new_item])

          dependency_store.load
        end

        it { is_expected.to be_a(Nanoc::Core::OutdatednessReasons::ItemCollectionExtended) }

        it 'includes proper raw_content props' do
          expect(subject.objects.map(&:identifier).map(&:to_s)).to eq(['/newblahz.md'])
        end
      end
    end

    context 'with layout collection' do
      let(:obj) { layouts }

      context 'no new layouts' do
        it { is_expected.to be_nil }
      end

      context 'new layouts' do
        before do
          dependency_store.store

          new_layout = Nanoc::Core::Layout.new('stuff', {}, '/newblahz.md')
          dependency_store.layouts = Nanoc::Core::LayoutCollection.new(config, layouts.to_a + [new_layout])

          dependency_store.load
        end

        it { is_expected.to be_a(Nanoc::Core::OutdatednessReasons::LayoutCollectionExtended) }

        it 'includes proper raw_content props' do
          expect(subject.objects.map(&:identifier).map(&:to_s)).to eq(['/newblahz.md'])
        end
      end
    end
  end

  describe '#outdated_due_to_dependencies?' do
    subject { outdatedness_checker.send(:outdated_due_to_dependencies?, item) }

    let(:checksum_store) { Nanoc::Core::ChecksumStore.new(config: config, objects: items.to_a + layouts.to_a) }

    let(:other_item) { Nanoc::Core::Item.new('other stuff', {}, '/other.md') }
    let(:other_item_rep) { Nanoc::Core::ItemRep.new(other_item, :default) }

    let(:config) { Nanoc::Core::Configuration.new(dir: Dir.getwd).with_defaults }

    let(:items) { Nanoc::Core::ItemCollection.new(config, [item, other_item]) }

    let(:old_action_sequence_for_other_item_rep) do
      Nanoc::Core::ActionSequenceBuilder.build(other_item_rep) do |b|
        b.add_filter(:erb, {})
      end
    end

    let(:new_action_sequence_for_other_item_rep) { old_action_sequence_for_other_item_rep }

    let(:action_sequences) do
      {
        item_rep => new_action_sequence_for_item_rep,
        other_item_rep => new_action_sequence_for_other_item_rep,
      }
    end

    before do
      reps << other_item_rep
      action_sequence_store[other_item_rep] = old_action_sequence_for_other_item_rep.serialize
      checksum_store.add(item)
      checksum_store.add(other_item)
      checksum_store.add(config)

      allow(site).to receive(:code_snippets).and_return([])
      allow(site).to receive(:config).and_return(config)
    end

    context 'transitive dependency' do
      let(:distant_item) { Nanoc::Core::Item.new('distant stuff', {}, '/distant.md') }
      let(:distant_item_rep) { Nanoc::Core::ItemRep.new(distant_item, :default) }

      let(:items) do
        Nanoc::Core::ItemCollection.new(config, [item, other_item, distant_item])
      end

      let(:action_sequences) do
        {
          item_rep => new_action_sequence_for_item_rep,
          other_item_rep => new_action_sequence_for_other_item_rep,
          distant_item_rep => new_action_sequence_for_other_item_rep,
        }
      end

      before do
        reps << distant_item_rep
        checksum_store.add(distant_item)
        action_sequence_store[distant_item_rep] = old_action_sequence_for_other_item_rep.serialize
      end

      context 'on attribute + attribute' do
        before do
          dependency_store.record_dependency(item, other_item, attributes: true)
          dependency_store.record_dependency(other_item, distant_item, attributes: true)
        end

        context 'distant attribute changed' do
          before { distant_item.attributes[:title] = 'omg new title' }

          it 'has correct outdatedness of item' do
            expect(outdatedness_checker.send(:outdated_due_to_dependencies?, item)).to be(false)
          end

          it 'has correct outdatedness of other item' do
            expect(outdatedness_checker.send(:outdated_due_to_dependencies?, other_item)).to be(true)
          end
        end

        context 'distant raw content changed' do
          before { distant_item.content = Nanoc::Core::TextualContent.new('omg new content') }

          it 'has correct outdatedness of item' do
            expect(outdatedness_checker.send(:outdated_due_to_dependencies?, item)).to be(false)
          end

          it 'has correct outdatedness of other item' do
            expect(outdatedness_checker.send(:outdated_due_to_dependencies?, other_item)).to be(false)
          end
        end
      end

      context 'on compiled content + attribute' do
        before do
          dependency_store.record_dependency(item, other_item, compiled_content: true)
          dependency_store.record_dependency(other_item, distant_item, attributes: true)
        end

        context 'distant attribute changed' do
          before { distant_item.attributes[:title] = 'omg new title' }

          it 'has correct outdatedness of item' do
            expect(outdatedness_checker.send(:outdated_due_to_dependencies?, item)).to be(true)
          end

          it 'has correct outdatedness of other item' do
            expect(outdatedness_checker.send(:outdated_due_to_dependencies?, other_item)).to be(true)
          end
        end

        context 'distant raw content changed' do
          before { distant_item.content = Nanoc::Core::TextualContent.new('omg new content') }

          it 'has correct outdatedness of item' do
            expect(outdatedness_checker.send(:outdated_due_to_dependencies?, item)).to be(false)
          end

          it 'has correct outdatedness of other item' do
            expect(outdatedness_checker.send(:outdated_due_to_dependencies?, other_item)).to be(false)
          end
        end
      end
    end

    context 'only generic attribute dependency' do
      before do
        dependency_store.record_dependency(item, other_item, attributes: true)
      end

      context 'attribute changed' do
        before { other_item.attributes[:title] = 'omg new title' }

        it { is_expected.to be(true) }
      end

      context 'raw content changed' do
        before { other_item.content = Nanoc::Core::TextualContent.new('omg new content') }

        it { is_expected.to be(false) }
      end

      context 'attribute + raw content changed' do
        before { other_item.attributes[:title] = 'omg new title' }

        before { other_item.content = Nanoc::Core::TextualContent.new('omg new content') }

        it { is_expected.to be(true) }
      end

      context 'path changed' do
        let(:new_action_sequence_for_other_item_rep) do
          Nanoc::Core::ActionSequenceBuilder.build(other_item_rep) do |b|
            b.add_filter(:erb, {})
            b.add_snapshot(:donkey, '/giraffe.txt')
          end
        end

        it { is_expected.to be(false) }
      end
    end

    context 'only specific attribute dependency' do
      before do
        dependency_store.record_dependency(item, other_item, attributes: [:title])
      end

      context 'attribute changed' do
        before { other_item.attributes[:title] = 'omg new title' }

        it { is_expected.to be(true) }
      end

      context 'other attribute changed' do
        before { other_item.attributes[:subtitle] = 'tagline here' }

        it { is_expected.to be(false) }
      end

      context 'raw content changed' do
        before { other_item.content = Nanoc::Core::TextualContent.new('omg new content') }

        it { is_expected.to be(false) }
      end

      context 'attribute + raw content changed' do
        before { other_item.attributes[:title] = 'omg new title' }

        before { other_item.content = Nanoc::Core::TextualContent.new('omg new content') }

        it { is_expected.to be(true) }
      end

      context 'other attribute + raw content changed' do
        before { other_item.attributes[:subtitle] = 'tagline here' }

        before { other_item.content = Nanoc::Core::TextualContent.new('omg new content') }

        it { is_expected.to be(false) }
      end

      context 'path changed' do
        let(:new_action_sequence_for_other_item_rep) do
          Nanoc::Core::ActionSequenceBuilder.build(other_item_rep) do |b|
            b.add_filter(:erb, {})
            b.add_snapshot(:donkey, '/giraffe.txt')
          end
        end

        it { is_expected.to be(false) }
      end
    end

    context 'generic dependency on config' do
      before do
        dependency_store.record_dependency(item, config, attributes: true)
      end

      context 'nothing changed' do
        it { is_expected.to be(false) }
      end

      context 'attribute changed' do
        before { config[:title] = 'omg new title' }

        it { is_expected.to be(true) }
      end

      context 'other attribute changed' do
        before { config[:subtitle] = 'tagline here' }

        it { is_expected.to be(true) }
      end
    end

    context 'specific dependency on config' do
      before do
        dependency_store.record_dependency(item, config, attributes: [:title])
      end

      context 'nothing changed' do
        it { is_expected.to be(false) }
      end

      context 'attribute changed' do
        before { config[:title] = 'omg new title' }

        it { is_expected.to be(true) }
      end

      context 'other attribute changed' do
        before { config[:subtitle] = 'tagline here' }

        it { is_expected.to be(false) }
      end
    end

    context 'only raw content dependency' do
      before do
        dependency_store.record_dependency(item, other_item, raw_content: true)
      end

      context 'attribute changed' do
        before { other_item.attributes[:title] = 'omg new title' }

        it { is_expected.to be(false) }
      end

      context 'raw content changed' do
        before { other_item.content = Nanoc::Core::TextualContent.new('omg new content') }

        it { is_expected.to be(true) }
      end

      context 'attribute + raw content changed' do
        before { other_item.attributes[:title] = 'omg new title' }

        before { other_item.content = Nanoc::Core::TextualContent.new('omg new content') }

        it { is_expected.to be(true) }
      end

      context 'path changed' do
        let(:new_action_sequence_for_other_item_rep) do
          Nanoc::Core::ActionSequenceBuilder.build(other_item_rep) do |b|
            b.add_filter(:erb, {})
            b.add_snapshot(:donkey, '/giraffe.txt')
          end
        end

        it { is_expected.to be(false) }
      end
    end

    context 'only path dependency' do
      before do
        dependency_store.record_dependency(item, other_item, raw_content: true)
      end

      context 'attribute changed' do
        before { other_item.attributes[:title] = 'omg new title' }

        it { is_expected.to be(false) }
      end

      context 'raw content changed' do
        before { other_item.content = Nanoc::Core::TextualContent.new('omg new content') }

        it { is_expected.to be(true) }
      end

      context 'path changed' do
        let(:new_action_sequence_for_other_item_rep) do
          Nanoc::Core::ActionSequenceBuilder.build(other_item_rep) do |b|
            b.add_filter(:erb, {})
            b.add_snapshot(:donkey, '/giraffe.txt')
          end
        end

        it { is_expected.to be(false) }
      end
    end

    context 'attribute + raw content dependency' do
      before do
        dependency_store.record_dependency(item, other_item, attributes: true, raw_content: true)
      end

      context 'attribute changed' do
        before { other_item.attributes[:title] = 'omg new title' }

        it { is_expected.to be(true) }
      end

      context 'raw content changed' do
        before { other_item.content = Nanoc::Core::TextualContent.new('omg new content') }

        it { is_expected.to be(true) }
      end

      context 'attribute + raw content changed' do
        before { other_item.attributes[:title] = 'omg new title' }

        before { other_item.content = Nanoc::Core::TextualContent.new('omg new content') }

        it { is_expected.to be(true) }
      end

      context 'rules changed' do
        let(:new_action_sequence_for_other_item_rep) do
          Nanoc::Core::ActionSequenceBuilder.build(other_item_rep) do |b|
            b.add_filter(:erb, {})
            b.add_filter(:donkey, {})
          end
        end

        it { is_expected.to be(false) }
      end
    end

    context 'attribute + other dependency' do
      before do
        dependency_store.record_dependency(item, other_item, attributes: true, path: true)
      end

      context 'attribute changed' do
        before { other_item.attributes[:title] = 'omg new title' }

        it { is_expected.to be(true) }
      end

      context 'raw content changed' do
        before { other_item.content = Nanoc::Core::TextualContent.new('omg new content') }

        it { is_expected.to be(false) }
      end
    end

    context 'other dependency' do
      before do
        dependency_store.record_dependency(item, other_item, path: true)
      end

      context 'attribute changed' do
        before { other_item.attributes[:title] = 'omg new title' }

        it { is_expected.to be(false) }
      end

      context 'raw content changed' do
        before { other_item.content = Nanoc::Core::TextualContent.new('omg new content') }

        it { is_expected.to be(false) }
      end
    end

    context 'only item collection dependency' do
      context 'dependency on any new item' do
        before do
          dependency_tracker = Nanoc::Core::DependencyTracker.new(dependency_store)
          dependency_tracker.enter(item)
          dependency_tracker.bounce(items, raw_content: true)
          dependency_store.store
        end

        context 'nothing changed' do
          it { is_expected.to be(false) }
        end

        context 'item added' do
          before do
            new_item = Nanoc::Core::Item.new('stuff', {}, '/newblahz.md')
            dependency_store.items = Nanoc::Core::ItemCollection.new(config, items.to_a + [new_item])
            dependency_store.load
          end

          it { is_expected.to be(true) }
        end

        context 'item removed' do
          before do
            dependency_store.items = Nanoc::Core::ItemCollection.new(config, [])
            dependency_store.load
          end

          it { is_expected.to be(false) }
        end
      end

      context 'dependency on specific new items (string)' do
        before do
          dependency_tracker = Nanoc::Core::DependencyTracker.new(dependency_store)
          dependency_tracker.enter(item)
          dependency_tracker.bounce(items, raw_content: ['/new*'])
          dependency_store.store
        end

        context 'nothing changed' do
          it { is_expected.to be(false) }
        end

        context 'matching item added' do
          before do
            new_item = Nanoc::Core::Item.new('stuff', {}, '/newblahz.md')
            dependency_store.items = Nanoc::Core::ItemCollection.new(config, items.to_a + [new_item])
            dependency_store.load
          end

          it { is_expected.to be(true) }
        end

        context 'non-matching item added' do
          before do
            new_item = Nanoc::Core::Item.new('stuff', {}, '/nublahz.md')
            dependency_store.items = Nanoc::Core::ItemCollection.new(config, items.to_a + [new_item])
            dependency_store.load
          end

          it { is_expected.to be(false) }
        end

        context 'item removed' do
          before do
            dependency_store.items = Nanoc::Core::ItemCollection.new(config, [])
            dependency_store.load
          end

          it { is_expected.to be(false) }
        end
      end

      context 'dependency on specific new items (regex)' do
        before do
          dependency_tracker = Nanoc::Core::DependencyTracker.new(dependency_store)
          dependency_tracker.enter(item)
          dependency_tracker.bounce(items, raw_content: [%r{^/new.*}])
          dependency_store.store
        end

        context 'nothing changed' do
          it { is_expected.to be(false) }
        end

        context 'matching item added' do
          before do
            new_item = Nanoc::Core::Item.new('stuff', {}, '/newblahz.md')
            dependency_store.items = Nanoc::Core::ItemCollection.new(config, items.to_a + [new_item])
            dependency_store.load
          end

          it { is_expected.to be(true) }
        end

        context 'non-matching item added' do
          before do
            new_item = Nanoc::Core::Item.new('stuff', {}, '/nublahz.md')
            dependency_store.items = Nanoc::Core::ItemCollection.new(config, items.to_a + [new_item])
            dependency_store.load
          end

          it { is_expected.to be(false) }
        end

        context 'item removed' do
          before do
            dependency_store.items = Nanoc::Core::ItemCollection.new(config, [])
            dependency_store.load
          end

          it { is_expected.to be(false) }
        end
      end
    end

    context 'only layout collection dependency' do
      context 'dependency on any new layout' do
        before do
          dependency_tracker = Nanoc::Core::DependencyTracker.new(dependency_store)
          dependency_tracker.enter(item)
          dependency_tracker.bounce(layouts, raw_content: true)
          dependency_store.store
        end

        context 'nothing changed' do
          it { is_expected.to be(false) }
        end

        context 'layout added' do
          before do
            new_layout = Nanoc::Core::Layout.new('stuff', {}, '/newblahz.md')
            dependency_store.layouts = Nanoc::Core::LayoutCollection.new(config, layouts.to_a + [new_layout])
            dependency_store.load
          end

          it { is_expected.to be(true) }
        end

        context 'layout removed' do
          before do
            dependency_store.layouts = Nanoc::Core::LayoutCollection.new(config, [])
            dependency_store.load
          end

          it { is_expected.to be(false) }
        end
      end

      context 'dependency on specific new layouts (string)' do
        before do
          dependency_tracker = Nanoc::Core::DependencyTracker.new(dependency_store)
          dependency_tracker.enter(item)
          dependency_tracker.bounce(layouts, raw_content: ['/new*'])
          dependency_store.store
        end

        context 'nothing changed' do
          it { is_expected.to be(false) }
        end

        context 'matching layout added' do
          before do
            new_layout = Nanoc::Core::Layout.new('stuff', {}, '/newblahz.md')
            dependency_store.layouts = Nanoc::Core::LayoutCollection.new(config, layouts.to_a + [new_layout])
            dependency_store.load
          end

          it { is_expected.to be(true) }
        end

        context 'non-matching layout added' do
          before do
            new_layout = Nanoc::Core::Layout.new('stuff', {}, '/nublahz.md')
            dependency_store.layouts = Nanoc::Core::LayoutCollection.new(config, layouts.to_a + [new_layout])
            dependency_store.load
          end

          it { is_expected.to be(false) }
        end

        context 'layout removed' do
          before do
            dependency_store.layouts = Nanoc::Core::LayoutCollection.new(config, [])
            dependency_store.load
          end

          it { is_expected.to be(false) }
        end
      end

      context 'dependency on specific new layouts (regex)' do
        before do
          dependency_tracker = Nanoc::Core::DependencyTracker.new(dependency_store)
          dependency_tracker.enter(item)
          dependency_tracker.bounce(layouts, raw_content: [%r{^/new.*}])
          dependency_store.store
        end

        context 'nothing changed' do
          it { is_expected.to be(false) }
        end

        context 'matching layout added' do
          before do
            new_layout = Nanoc::Core::Layout.new('stuff', {}, '/newblahz.md')
            dependency_store.layouts = Nanoc::Core::LayoutCollection.new(config, layouts.to_a + [new_layout])
            dependency_store.load
          end

          it { is_expected.to be(true) }
        end

        context 'non-matching layout added' do
          before do
            new_layout = Nanoc::Core::Layout.new('stuff', {}, '/nublahz.md')
            dependency_store.layouts = Nanoc::Core::LayoutCollection.new(config, layouts.to_a + [new_layout])
            dependency_store.load
          end

          it { is_expected.to be(false) }
        end

        context 'layout removed' do
          before do
            dependency_store.layouts = Nanoc::Core::LayoutCollection.new(config, [])
            dependency_store.load
          end

          it { is_expected.to be(false) }
        end
      end
    end
  end
end
