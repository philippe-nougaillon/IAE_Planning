class EtudiantPolicy < ApplicationPolicy
    class Scope < Scope
      def resolve
        scope
      end
    end
  
    def index?
      user
    end

end