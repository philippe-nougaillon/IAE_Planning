class Formation < ActiveRecord::Base
	
	audited
	
	has_many :users
	has_many :cours, dependent: :destroy
	has_many :intervenants, through: :cours
	has_many :documents, dependent: :destroy
	
	has_many :unites
	accepts_nested_attributes_for :unites, allow_destroy:true, reject_if: lambda {|attributes| attributes['num'].blank?}

	has_many :etudiants
	accepts_nested_attributes_for :etudiants, allow_destroy:true, reject_if: lambda {|attributes| attributes['nom'].blank?}

	belongs_to :user

	validates :nom, :nbr_etudiants, :nbr_heures, :abrg, presence: true
	validates :nom, uniqueness: {scope: :promo}
	
	default_scope { where("archive is null OR archive is false") }
	default_scope { order(:nom, :promo) } 
	
	def nom_promo
		self.promo.blank? ? self.nom : "#{self.nom} - #{self.promo}" 
	end

	def nom_promo_full
		self.promo.blank? ? self.nom : "#{self.nom} | Promo: #{self.promo}" 
	end

	def nom_promo_etudiants
		self.promo.blank? ? "#{self.nom} (#{self.nbr_etudiants}E)"  : "#{self.nom} - #{self.promo} (#{self.nbr_etudiants}E)" 
	end

	def self.for_select
		{
		  'Formations catalogue' => where(hors_catalogue:false).map { |i| i.nom },
		  'Formations hors catalogue' => where(hors_catalogue:true).map { |i| i.nom }
		}
	end

end

