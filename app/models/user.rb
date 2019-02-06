# Encoding: UTF-8

class User < ActiveRecord::Base
  
  audited
  
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable :registerable,
  devise :database_authenticatable,
         :recoverable, :rememberable, :trackable, :validatable

  belongs_to :formation   

  validates :nom, :prénom, presence: true    

  default_scope { order(:nom, :prénom) } 

  def username 
  	"#{self.email.split('@').first} #{self.admin? ? "(admin)" : '' }"
  end

  def isRHGroupMember?
      ['philippe.nougaillon@gmail.com',
        'cunha.iae@univ-paris1.fr',
        'fitsch-mouras.iae@univ-paris1.fr',
        'manzano.iae@univ-paris1.fr',
        'denis.iae@univ-paris1.fr']
        .include?(self.email)
  end

end
