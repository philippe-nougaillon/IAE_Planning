# encoding: UTF-8

class EtudiantsController < ApplicationController
  before_action :set_etudiant, only: [:show, :edit, :update, :destroy]

  # GET /etudiants
  # GET /etudiants.json
  def index
    authorize Etudiant

    params[:column] ||= session[:column]
    params[:direction_etudiants] ||= session[:direction_etudiants]

    @etudiants = Etudiant.all

    unless params[:nom].blank?
      @etudiants = @etudiants.where("nom like ? OR nom_entreprise like ?", "%#{params[:nom]}%", "%#{params[:nom]}%")
    end

    unless params[:workflow_state].blank?
      @etudiants = @etudiants.where("etudiants.workflow_state = ?", params[:workflow_state].to_s.downcase)
    end

    unless params[:formation_id].blank?
      @etudiants = @etudiants.where(formation_id:params[:formation_id])
    end

    session[:column] = params[:column]
    session[:direction_etudiants] = params[:direction_etudiants]

    @etudiants = @etudiants
                    .includes(:formation)
                    .order("#{sort_column} #{sort_direction}")
                    .paginate(page: params[:page], per_page: 20)
  end

  # GET /etudiants/1
  # GET /etudiants/1.json
  def show
  end

  # GET /etudiants/new
  def new
    @etudiant = Etudiant.new
  end

  # GET /etudiants/1/edit
  def edit
  end

  # POST /etudiants
  # POST /etudiants.json
  def create
    @etudiant = Etudiant.new(etudiant_params)

    respond_to do |format|
      if @etudiant.save
        format.html { redirect_to @etudiant, notice: 'Etudiant créé avec succès.' }
        format.json { render :show, status: :created, location: @etudiant }
      else
        format.html { render :new }
        format.json { render json: @etudiant.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /etudiants/1
  # PATCH/PUT /etudiants/1.json
  def update
    respond_to do |format|
      if @etudiant.update(etudiant_params)
        format.html { redirect_to @etudiant, notice: 'Etudiant modifié avec succès.' }
        format.json { render :show, status: :ok, location: @etudiant }
      else
        format.html { render :edit }
        format.json { render json: @etudiant.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /etudiants/1
  # DELETE /etudiants/1.json
  def destroy
    @etudiant.destroy
    respond_to do |format|
      format.html { redirect_to etudiants_url, notice: 'Etudiant supprimé avec succès' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_etudiant
      @etudiant = Etudiant.find(params[:id])
    end

    def sortable_columns
      ['etudiants.nom', 'etudiants.date_de_naissance', 'etudiants.workflow_state', 'etudiants.nom_entreprise', 'etudiants.updated_at']
    end

    def sort_column
        sortable_columns.include?(params[:column]) ? params[:column] : "nom, prénom"
    end

    def sort_direction
        %w[asc desc].include?(params[:direction_etudiants]) ? params[:direction_etudiants] : "asc"
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def etudiant_params
      params.require(:etudiant)
            .permit(:formation_id, :nom, :prénom, :email, :mobile, :civilité, :nom_marital, :date_de_naissance, 
                    :lieu_naissance, :pays_naissance, :nationalité, :adresse, :cp, :ville, :dernier_ets, 
                    :dernier_diplôme, :cat_diplôme, :num_sécu, 
                    :num_apogée, :poste_occupé, :nom_entreprise, :adresse_entreprise, :cp_entreprise, :ville_entreprise,
                    :workflow_state)
    end
    
end
