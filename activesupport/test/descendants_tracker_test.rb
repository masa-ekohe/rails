# frozen_string_literal: true

require_relative "abstract_unit"
require "set"
require "active_support/descendants_tracker"

class DescendantsTrackerTest < ActiveSupport::TestCase
  setup do
    if ActiveSupport::DescendantsTracker.class_variable_defined?(:@@direct_descendants)
      @original_state = ActiveSupport::DescendantsTracker.class_variable_get(:@@direct_descendants).dup
      @original_state.each { |k, v| @original_state[k] = v.dup }
    end

    ActiveSupport::DescendantsTracker.clear
    eval <<~RUBY
      class Parent
        extend ActiveSupport::DescendantsTracker
      end

      class Child1 < Parent
      end

      class Child2 < Parent
      end

      class Grandchild1 < Child1
      end

      class Grandchild2 < Child1
      end
    RUBY
  end

  teardown do
    if ActiveSupport::DescendantsTracker.class_variable_defined?(:@@direct_descendants)
      ActiveSupport::DescendantsTracker.class_variable_get(:@@direct_descendants).replace(@original_state)
    end

    %i(Parent Child1 Child2 Grandchild1 Grandchild2).each do |name|
      if DescendantsTrackerTest.const_defined?(name)
        DescendantsTrackerTest.send(:remove_const, name)
      end
    end
  end

  test ".descendants" do
    assert_equal_sets [Child1, Grandchild1, Grandchild2, Child2], Parent.descendants
    assert_equal_sets [Grandchild1, Grandchild2], Child1.descendants
    assert_equal_sets [], Child2.descendants
  end

  test ".descendants with garbage collected classes" do
    # The Ruby GC (and most other GCs for that matter) are not fully precise.
    # When GC is run, the whole stack is scanned to mark any object reference
    # in registers. But some of these references might simply be leftovers from
    # previous method calls waiting to be overridden, and there's no definite
    # way to clear them. By executing this code in a distinct thread, we ensure
    # that such references are on a stack that will be entirely garbage
    # collected, effectively working around the problem.
    Thread.new do
      child_klass = Class.new(Parent)
      assert_equal_sets [Child1, Grandchild1, Grandchild2, Child2, child_klass], Parent.descendants
    end.join

    # Calling `GC.start` 4 times should trigger a full GC run
    4.times do
      GC.start
    end

    assert_equal_sets [Child1, Grandchild1, Grandchild2, Child2], Parent.descendants
  end

  test ".direct_descendants" do
    assert_deprecated do
      assert_equal_sets [Child1, Child2], Parent.direct_descendants
    end

    assert_deprecated do
      assert_equal_sets [Grandchild1, Grandchild2], Child1.direct_descendants
    end

    assert_deprecated do
      assert_equal_sets [], Child2.direct_descendants
    end
  end

  test ".subclasses" do
    [Parent, Child1, Child2].each do |klass|
      assert_equal assert_deprecated { klass.direct_descendants }, klass.subclasses
    end
  end

  test ".clear deletes all state" do
    ActiveSupport::DescendantsTracker.clear
    if ActiveSupport::DescendantsTracker.class_variable_defined?(:@@direct_descendants)
      assert_empty ActiveSupport::DescendantsTracker.class_variable_get(:@@direct_descendants)
    end
  end

  test ".clear(only) deletes the given classes only" do
    skip "Irrelevant for native Class#descendants" if ActiveSupport::DescendantsTracker.native?

    ActiveSupport::DescendantsTracker.clear(only: Set[Child2, Grandchild1])

    assert_equal_sets [Child1, Grandchild2], Parent.descendants
    assert_equal_sets [Grandchild2], Child1.descendants

    assert_equal_sets [Child1], assert_deprecated { Parent.direct_descendants }
    assert_equal_sets [Grandchild2], assert_deprecated { Child1.direct_descendants }
  end

  private
    def assert_equal_sets(expected, actual)
      assert_equal Set.new(expected), Set.new(actual)
    end
end
