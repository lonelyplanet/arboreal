require "active_support/core_ext/string/filters"

module Arboreal
  module InstanceMethods

    def path_string
      "#{ancestry_string}#{id}-"
    end

    def ancestor_ids
      ancestry_string.sub(/^-/, "").split("-").map { |x| x.to_i }
    end

    # return a scope matching all ancestors of this node
    def ancestors
      model_base_class.where(ancestor_conditions).order(:ancestry_string)
    end

    # return a scope matching all descendants of this node
    def descendants
      model_base_class.where(descendant_conditions)
    end

    # return a scope matching all descendants of this node, AND the node itself
    def subtree
      model_base_class.where(subtree_conditions)
    end

    # return a scope matching all siblings of this node (NOT including the node itself)
    def siblings
      model_base_class.where(sibling_conditions)
    end

    # return the root of the tree
    def root
      ancestors.first || self
    end

    private

    def model_base_class
      self.class.base_class
    end

    def table_name
      self.class.table_name
    end

    def ancestor_conditions
      ["id in (?)", ancestor_ids]
    end

    def descendant_conditions
      ["#{table_name}.ancestry_string LIKE ?", path_string + "%"]
    end

    def subtree_conditions
      [
        "#{table_name}.id = ? OR #{table_name}.ancestry_string LIKE ?",
        id, path_string + "%"
      ]
    end

    def sibling_conditions
      [
        "#{table_name}.id <> ? AND #{table_name}.parent_id = ?",
        id, parent_id
      ]
    end

    def populate_ancestry_string
      self.ancestry_string = nil if parent_id_changed?
      model_base_class.unscoped do
        self.ancestry_string ||= parent ? parent.path_string : "-"
      end
    end

    def validate_parent_not_ancestor
      if self.id
        if parent_id == self.id
          errors.add(:parent, "can't be the record itself")
        end
        if ancestor_ids.include?(self.id)
          errors.add(:parent, "can't be an ancestor")
        end
      end
    end

    def detect_ancestry_change
      if ancestry_string_changed? && !new_record?
        old_path_string = "#{ancestry_string_was}#{id}-"
        @ancestry_change = [old_path_string, path_string]
      end
    end

    def apply_ancestry_change_to_descendants
      if @ancestry_change
        old_ancestry_string, new_ancestry_string = *@ancestry_change
        self.class.connection.update(<<-SQL.squish)
          UPDATE #{table_name}
            SET ancestry_string = REPLACE(ancestry_string, '#{old_ancestry_string}', '#{new_ancestry_string}')
            WHERE ancestry_string LIKE '#{old_ancestry_string}%'
        SQL
        @ancestry_change = nil
      end
    end

  end
end
