module Nanoc::Int
  # Responsible for determining whether an item or a layout is outdated.
  #
  # @api private
  class OutdatednessChecker
    extend Nanoc::Int::Memoization

    include Nanoc::Int::ContractsSupport

    attr_reader :checksum_store
    attr_reader :dependency_store
    attr_reader :rule_memory_store
    attr_reader :action_provider
    attr_reader :site

    Reasons = Nanoc::Int::OutdatednessReasons
    Rules = Nanoc::Int::OutdatednessRules

    # @param [Nanoc::Int::Site] site
    # @param [Nanoc::Int::ChecksumStore] checksum_store
    # @param [Nanoc::Int::DependencyStore] dependency_store
    # @param [Nanoc::Int::RuleMemoryStore] rule_memory_store
    # @param [Nanoc::Int::ActionProvider] action_provider
    # @param [Nanoc::Int::ItemRepRepo] reps
    def initialize(site:, checksum_store:, dependency_store:, rule_memory_store:, action_provider:, reps:)
      @site = site
      @checksum_store = checksum_store
      @dependency_store = dependency_store
      @rule_memory_store = rule_memory_store
      @action_provider = action_provider
      @reps = reps

      @basic_outdatedness_reasons = {}
      @outdatedness_reasons = {}
      @objects_outdated_due_to_dependencies = {}
    end

    contract C::Or[Nanoc::Int::Item, Nanoc::Int::ItemRep, Nanoc::Int::Layout] => C::Bool
    # Checks whether the given object is outdated and therefore needs to be
    # recompiled.
    #
    # @param [Nanoc::Int::Item, Nanoc::Int::ItemRep, Nanoc::Int::Layout] obj The object
    #   whose outdatedness should be checked.
    #
    # @return [Boolean] true if the object is outdated, false otherwise
    def outdated?(obj)
      !outdatedness_reason_for(obj).nil?
    end

    contract C::Or[Nanoc::Int::Item, Nanoc::Int::ItemRep, Nanoc::Int::Layout] => C::Maybe[Reasons::Generic]
    # Calculates the reason why the given object is outdated.
    #
    # @param [Nanoc::Int::Item, Nanoc::Int::ItemRep, Nanoc::Int::Layout] obj The object
    #   whose outdatedness reason should be calculated.
    #
    # @return [Reasons::Generic, nil] The reason why the
    #   given object is outdated, or nil if the object is not outdated.
    def outdatedness_reason_for(obj)
      reason = basic_outdatedness_reason_for(obj)
      if reason.nil? && outdated_due_to_dependencies?(obj)
        reason = Reasons::DependenciesOutdated
      end
      reason
    end
    memoize :outdatedness_reason_for

    private

    contract C::Or[Nanoc::Int::Item, Nanoc::Int::ItemRep, Nanoc::Int::Layout] => C::Bool
    # Checks whether the given object is outdated and therefore needs to be
    # recompiled. This method does not take dependencies into account; use
    # {#outdated?} if you want to include dependencies in the outdatedness
    # check.
    #
    # @param [Nanoc::Int::Item, Nanoc::Int::ItemRep, Nanoc::Int::Layout] obj The object
    #   whose outdatedness should be checked.
    #
    # @return [Boolean] true if the object is outdated, false otherwise
    def basic_outdated?(obj)
      !basic_outdatedness_reason_for(obj).nil?
    end

    RULES_FOR_ITEM_REP =
      [
        Rules::RulesModified,
        Rules::PathsModified,
        Rules::ContentModified,
        Rules::AttributesModified,
        Rules::NotWritten,
        Rules::CodeSnippetsModified,
        Rules::ConfigurationModified,
      ].freeze

    RULES_FOR_LAYOUT =
      [
        Rules::RulesModified,
        Rules::ContentModified,
        Rules::AttributesModified,
      ].freeze

    def apply_rules(rules, obj, status = OutdatednessStatus.new)
      rules.inject(status) do |acc, rule|
        if !acc.useful_to_apply?(rule)
          acc
        elsif rule.instance.apply(obj, self)
          acc.update(rule.instance.reason)
        else
          acc
        end
      end
    end

    def apply_rules_multi(rules, objs)
      objs.inject(OutdatednessStatus.new) { |acc, elem| apply_rules(rules, elem, acc) }
    end

    contract C::Or[Nanoc::Int::Item, Nanoc::Int::ItemRep, Nanoc::Int::Layout] => C::Maybe[Reasons::Generic]
    # Calculates the reason why the given object is outdated. This method does
    # not take dependencies into account; use {#outdatedness_reason_for?} if
    # you want to include dependencies in the outdatedness check.
    #
    # @param [Nanoc::Int::Item, Nanoc::Int::ItemRep, Nanoc::Int::Layout] obj The object
    #   whose outdatedness reason should be calculated.
    #
    # @return [Reasons::Generic, nil] The reason why the
    #   given object is outdated, or nil if the object is not outdated.
    def basic_outdatedness_reason_for(obj)
      # FIXME: Stop using this; it is no longer accurate, as there can be >1 reasons
      basic_outdatedness_status_for(obj).reasons.first
    end

    def basic_outdatedness_status_for(obj)
      case obj
      when Nanoc::Int::ItemRep
        apply_rules(RULES_FOR_ITEM_REP, obj)
      when Nanoc::Int::Item
        apply_rules_multi(RULES_FOR_ITEM_REP, @reps[obj])
      when Nanoc::Int::Layout
        apply_rules(RULES_FOR_LAYOUT, obj)
      else
        raise "do not know how to check outdatedness of #{obj.inspect}"
      end
    end
    memoize :basic_outdatedness_status_for

    contract C::Or[Nanoc::Int::Item, Nanoc::Int::ItemRep, Nanoc::Int::Layout], Hamster::Set => C::Bool
    # Checks whether the given object is outdated due to dependencies.
    #
    # @param [Nanoc::Int::Item, Nanoc::Int::ItemRep, Nanoc::Int::Layout] obj The object
    #   whose outdatedness should be checked.
    #
    # @param [Set] processed The collection of items that has been visited
    #   during this outdatedness check. This is used to prevent checks for
    #   items that (indirectly) depend on their own from looping
    #   indefinitely. It should not be necessary to pass this a custom value.
    #
    # @return [Boolean] true if the object is outdated, false otherwise
    def outdated_due_to_dependencies?(obj, processed = Hamster::Set.new)
      # Convert from rep to item if necessary
      obj = obj.item if obj.is_a?(Nanoc::Int::ItemRep)

      # Get from cache
      if @objects_outdated_due_to_dependencies.key?(obj)
        return @objects_outdated_due_to_dependencies[obj]
      end

      # Check processed
      # Don’t return true; the false will be or’ed into a true if there
      # really is a dependency that is causing outdatedness.
      return false if processed.include?(obj)

      # Calculate
      is_outdated = dependency_store.dependencies_causing_outdatedness_of(obj).any? do |dep|
        dependency_causes_outdatedness?(dep) || outdated_due_to_dependencies?(dep.from, processed.merge([obj]))
      end

      # Cache
      @objects_outdated_due_to_dependencies[obj] = is_outdated

      # Done
      is_outdated
    end

    contract Nanoc::Int::Dependency => C::Bool
    def dependency_causes_outdatedness?(dependency)
      return true if dependency.from.nil?

      status = basic_outdatedness_status_for(dependency.from)
      (status.props.active & dependency.props.active).any?
    end
  end
end
