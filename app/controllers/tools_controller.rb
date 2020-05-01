# ENCODING: UTF-8

class ToolsController < ApplicationController  
  include ActionView::Helpers::NumberHelper

  require 'csv'
  require 'capture_stdout'

  def index
    authorize :tool, :index?
  end

  def import_csv_do
    if params[:upload] and !params[:formation_id].blank?
      
      # Enregistre le fichier localement (format = Date + nom du fichier)
      filename = I18n.l(Time.now, format: :long) + ' - ' + params[:upload].original_filename
      file_with_path = Rails.root.join('public', 'tmp', filename)
      File.open(file_with_path, 'wb') do |file|
        file.write(params[:upload].read)
      end

      log = ImportLog.new(model_type: 'Cours', fichier: filename, user_id: current_user.id)

      @importes = @errors = 0 
      index = 1

      CSV.foreach(file_with_path, headers: true, col_sep: ';', quote_char:'"', encoding: 'UTF-8') do |row|
        index += 1

        intervenant = nil
        if row['Intervenant']
          if row['Intervenant'] == 'A CONFIRMER'
            intervenant = Intervenant.where(nom:'A', prenom:'CONFIRMER').first
          else  
            nom = row['Intervenant'].strip.split(' ').first.upcase
            prenom = row['Intervenant'].strip.split(' ').last
            intervenant = Intervenant.where(nom:nom, prenom:prenom).first_or_initialize
            if intervenant.new_record?
              intervenant.email = "?"
              intervenant.save if params[:save] == 'true'
            end
          end
        end

        # MAJ cours existant ? si l'id est égal à 0 => c'est une création
        id = row[0].to_i 
        if id == 0
          cours = Cour.new
        else
          if Cour.exists?(id)
            cours = Cour.find(id)
          else
            cours = Cour.new
          end
        end

        debut = Time.parse(row['Date début'] + " " + row['Heure début'] + 'UTC')
        fin   = Time.parse(row['Date fin'] + " " + row['Heure fin'] + 'UTC')
        cours.debut = debut
        cours.fin = fin
        cours.duree = ((fin - debut)/3600)
        cours.intervenant_id = intervenant.id
        cours.formation_id = params[:formation_id]

        cours.ue = row['UE'] ? row['UE'].gsub(' ','') : ""
        cours.nom = row['Intitulé']
        cours.elearning = true if row['E-learning?'] == 'OUI'
        cours.hors_service_statutaire = true if row['HSS?'] == 'OUI'

        msg = "COURS #{cours.new_record? ? 'NEW' : 'UPDATE'} => id:#{id} changes:#{cours.changes}"

        if cours.valid? 
          cours.save if params[:save] == 'true'
        else
          msg << " || ERREURS: " + cours.errors.messages.map{|m| "#{m.first} => #{m.last}"}.join(',')
        end

        _etat = ( cours.valid? ? ImportLogLine.etats[:succès] : ImportLogLine.etats[:echec]) 
        log.import_log_lines.build(etat: _etat, num_ligne: index, message: msg)

        cours.valid? ? @importes += 1 : @errors += 1 
      end

      _etat = if @errors.zero?
        ImportLog.etats[:succès] 
      else 
        if @errors < @importes 
          ImportLog.etats[:warning]
        else
          ImportLog.etats[:echec]
        end
      end   
      
      log.update(etat: _etat, nbr_lignes: @importes + @errors, lignes_importees: @importes)
      log.update(message: (params[:save] == 'true' ? "Importation" : "Simulation") )
      log.update(message: log.message + " | Formation: #{Formation.find(params[:formation_id]).try(:nom)}" )
      if @errors > 0
        log.update(message: log.message + " | #{@errors} lignes rejetées !")
      end   
      log.save
      
      flash[:notice] = "L'importation a bien été exécutée"
      redirect_to import_logs_path
    else
      flash[:error] = "Manque le fichier source ou la formation pour pouvoir lancer l'importation !"
      redirect_to action: 'import'
    end  
  end

  def import_do
    if params[:upload] and !params[:formation_id].blank?
      
      # Enregistre le fichier localement (format = Date + nom du fichier)
      filename = I18n.l(Time.now, format: :long) + ' - ' + params[:upload].original_filename
      file_with_path = Rails.root.join('public', 'tmp', filename)
      File.open(file_with_path, 'wb') do |file|
        file.write(params[:upload].read)
      end

      log = ImportLog.new(model_type: 'Cours', fichier: filename, user_id: current_user.id)

      @importes = @errors = 0 
      index = 1

      # IMPORT XLS
      Spreadsheet.client_encoding = 'UTF-8'
      book = Spreadsheet.open file_with_path
      sheet1 = book.worksheet 0

      headers = Cour.xls_headers

      sheet1.each 1 do |row|
        index += 1

        next unless row[0]

        # MAJ cours existant ? si l'id est égal à 0 => c'est une création
        id = row[0].to_i 
        if id == 0
          cours = Cour.new
        else
          if Cour.exists?(id)
            cours = Cour.find(id)
          else
            cours = Cour.new
          end
        end

        jour_debut = row[headers.index 'Date_début']
        if jour_debut.class == Date
          jour_debut = jour_debut.day.to_s + "/" + jour_debut.month.to_s + "/" + jour_debut.year.to_s        
        end
          
        jour_fin = row[headers.index 'Date_fin']
        if jour_fin.class == Date
          jour_fin = jour_fin.day.to_s + "/" + jour_fin.month.to_s + "/" + jour_fin.year.to_s        
        end

        horaire_debut = row[headers.index 'Heure_début']
        # si Excel converti la colone heure en DateHeure, on ne prend que l'heure et minute
        if horaire_debut.class == DateTime
          horaire_debut = horaire_debut.hour.to_s + ":" + horaire_debut.minute.to_s
        end  

        horaire_fin = row[headers.index 'Heure_fin']
        if horaire_fin.class == DateTime
          horaire_fin = horaire_fin.hour.to_s + ":" + horaire_fin.minute.to_s
        end  

        debut = Time.parse(jour_debut + " " + horaire_debut + 'UTC')
        fin   = Time.parse(jour_fin + " " +  horaire_fin + 'UTC')

        intervenant = nil
        if row[headers.index 'Intervenant']
          if row[headers.index 'Intervenant'] == 'A CONFIRMER'
            intervenant = Intervenant.where(nom:'A', prenom:'CONFIRMER').first
          else  
            nom = row[headers.index 'Intervenant'].strip.split(' ').first.upcase
            prenom = row[headers.index 'Intervenant'].strip.split(' ').last
            intervenant = Intervenant.where(nom:nom, prenom:prenom).first_or_initialize
            if intervenant.new_record?
              intervenant.email = "?"
              intervenant.save if params[:save] == 'true'
            end
          end
        end

        binome = nil
        if row[headers.index 'Binôme']
          nom_binome = row[headers.index 'Binôme'].strip.split(' ').first.upcase
          prenom_binome = row[headers.index 'Binôme'].strip.split(' ').last
          binome = Intervenant.where(nom: nom_binome, prenom: prenom_binome).first_or_initialize
        end

        cours.debut = debut
        cours.fin = fin
        cours.duree = ((fin - debut)/3600)
        cours.intervenant = intervenant
        cours.intervenant_binome = binome
        cours.formation_id = params[:formation_id]

        cours.ue = row[headers.index 'UE'] ? row[headers.index 'UE'].gsub(' ','') : ""
        cours.nom = row[headers.index 'Intitulé']
        cours.elearning = true if row[headers.index 'E-learning?'].try(:upcase) == 'OUI'
        cours.hors_service_statutaire = true if row[headers.index 'HSS?'].try(:upcase) == 'OUI'

        msg = "COURS #{cours.new_record? ? 'NEW' : 'UPDATE'} => id:#{id} changes:#{cours.changes}"

        if cours.valid? 
          cours.save if params[:save] == 'true'
        else
          msg << " || ERREURS: " + cours.errors.messages.map{|m| "#{m.first} => #{m.last}"}.join(',')
        end

        _etat = ( cours.valid? ? ImportLogLine.etats[:succès] : ImportLogLine.etats[:echec]) 
        log.import_log_lines.build(etat: _etat, num_ligne: index, message: msg)

        cours.valid? ? @importes += 1 : @errors += 1 
      end

      _etat = if @errors.zero?
        ImportLog.etats[:succès] 
      else 
        if @errors < @importes 
          ImportLog.etats[:warning]
        else
          ImportLog.etats[:echec]
        end
      end   
      
      log.update(etat: _etat, nbr_lignes: @importes + @errors, lignes_importees: @importes)
      log.update(message: (params[:save] == 'true' ? "Importation" : "Simulation") )
      log.update(message: log.message + " | Formation: #{Formation.find(params[:formation_id]).try(:nom)}" )
      if @errors > 0
        log.update(message: log.message + " | #{@errors} lignes rejetées !")
      end   
      log.save
      
      flash[:notice] = "L'importation a bien été exécutée"
      redirect_to import_logs_path
    else
      flash[:error] = "Manque le fichier source ou la formation pour pouvoir lancer l'importation !"
      redirect_to action: 'import'
    end  
  end

  def import_intervenants
  end

  def import_intervenants_do
    if params[:upload]
    	
      # Enregistre le fichier localement (format = Date + nom du fichier)
      filename = I18n.l(Time.now, format: :long) + ' - ' + params[:upload].original_filename

      file_with_path = Rails.root.join('public', 'tmp', filename)
      File.open(file_with_path, 'wb') do |file|
        file.write(params[:upload].read)
      end

      log = ImportLog.new(model_type: 'Intervenants', fichier: filename, user_id: current_user.id)

      @importes = @errors = 0 
      index = 1

      # IMPORT XLS
      Spreadsheet.client_encoding = 'UTF-8'
      book = Spreadsheet.open file_with_path
      sheet1 = book.worksheet 0
      headers = Intervenant.xls_headers

      sheet1.each 1 do |row|
        index += 1

        next unless row[0]

        intervenant = Intervenant
                            .where("lower(nom) = ? AND lower(prenom) = ?", 
                              row[headers.index 'Nom'].strip.downcase, 
                              row[headers.index 'Prénom'].strip.downcase)
                            .first_or_initialize

        intervenant.nom = row[headers.index 'Nom'].strip.upcase 
        intervenant.prenom = row[headers.index 'Prénom'].strip
        intervenant.email = row[headers.index 'Email']
        intervenant.linkedin_url = row[headers.index 'Linkedin_url']
        intervenant.titre1 = row[headers.index 'Titre1']
        intervenant.titre2 = row[headers.index 'Titre2']
        intervenant.status = row[headers.index 'Statut']
        intervenant.spécialité = row[headers.index 'Spécialité']
        intervenant.téléphone_fixe = row[headers.index 'Téléphone_fixe']
        intervenant.téléphone_mobile = row[headers.index 'Téléphone_mobile']
        intervenant.bureau = row[headers.index 'Bureau']

        # MAJ existant ? si l'id est égal à 0 => c'est une création
        msg = "INTERVENANT #{intervenant.new_record? ? 'NEW' : 'UPDATE'} => id:#{intervenant.id} changes:#{intervenant.changes}"

        if intervenant.valid? 
          intervenant.save if params[:save] == 'true'
        else
          msg << " || ERREURS: " + intervenant.errors.messages.map{|m| "#{m.first} => #{m.last}"}.join(',')
        end

        _etat = ( intervenant.valid? ? ImportLogLine.etats[:succès] : ImportLogLine.etats[:echec]) 
        log.import_log_lines.build(etat: _etat, num_ligne: index, message: msg)

        intervenant.valid? ? @importes += 1 : @errors += 1 
      end

      _etat = if @errors.zero?
        ImportLog.etats[:succès] 
      else 
        if @errors < @importes 
          ImportLog.etats[:warning]
        else
          ImportLog.etats[:echec]
        end
      end   
      
      log.update(etat: _etat, nbr_lignes: @importes + @errors, lignes_importees: @importes)
      log.update(message: (params[:save] == 'true' ? "Importation" : "Simulation") )
 
      if @errors > 0
        log.update(message: log.message + " | #{@errors} lignes rejetées !")
      end   
      log.save
      
      flash[:notice] = "L'importation a bien été exécutée"
      redirect_to import_logs_path
    else
      flash[:error] = "Manque le fichier source pour pouvoir lancer l'importation !"
      redirect_to action: 'import'
    end  

  end

  def import_utilisateurs
    authorize :tool, :import_utilisateurs?
  end

  def import_utilisateurs_do
    authorize :tool, :import_utilisateurs?
    
    if params[:upload]
    	
      # Enregistre le fichier localement
      file_with_path = Rails.root.join('public', 'tmp', params[:upload].original_filename)
      File.open(file_with_path, 'wb') do |file|
          file.write(params[:upload].read)
      end

      # capture output
      @stream = capture_stdout do
        @importes = @errors = 0	

        index = 0

        CSV.foreach(file_with_path, headers:true, col_sep:';', quote_char:'"', encoding:'UTF-8') do |row|
          index += 1

          generated_password = Devise.friendly_token.first(12)
          user = User.new(email:row['email'], nom:row['nom'].strip, prénom:row['prénom'].strip, mobile:row['mobile'], 
                  password:generated_password, formation_id:params[:formation_id])

          user.admin = true if row['admin?'] == 'admin'
           
          if user.valid? 
            user.save if params[:save] == 'true'
            UserMailer.welcome_email(user.id, generated_password).deliver_later if params[:save] == 'true'
            
            @importes += 1
          else
            puts "Ligne ##{index}"
            puts "!! user INVALIDE !! Erreur => #{user.errors.messages} | Source: #{row}"
            puts
            # puts user.changes
            @errors += 1
          end
          puts "- -" * 40
          puts
        end
        puts "----------- Les modifications n'ont pas été enregistrées ! ---------------" unless params[:save] == 'true'
        puts

        puts "=" * 40
        puts "Lignes importées: #{@importes} | Lignes ignorées: #{@errors}"
        puts "=" * 40
      end

      # save output            
      #@now = DateTime.now.to_s
      #File.open("public/Documents/Import_logements-#{@now}.txt", "w") { |file| file.write @out }
    else
      flash[:error] = "Manque le fichier source ou la formation pour pouvoir lancer l'importation !"
      redirect_to action: 'import_utilisateurs'
    end  
  end

  def import_etudiants
  end

  def import_etudiants_do
    if params[:upload] 

      unless params[:formation_id].blank?
        formation_id = params[:formation_id]
        workflow_state = :étudiant
      else
        formation_id = nil
        workflow_state = :prospect
      end

      # Enregistre le fichier localement (format = Date + nom du fichier)
      filename = I18n.l(Time.now, format: :long) + ' - ' + params[:upload].original_filename

      file_with_path = Rails.root.join('public', 'tmp', filename)
      File.open(file_with_path, 'wb') do |file|
        file.write(params[:upload].read)
      end

      log = ImportLog.new(model_type: 'Etudiants', fichier: filename, user_id: current_user.id)

      @importes = @errors = 0 
      index = 1

      # IMPORT XLS
      Spreadsheet.client_encoding = 'UTF-8'
      book = Spreadsheet.open file_with_path
      sheet1 = book.worksheet 0
      headers = Etudiant.xls_headers

      sheet1.each 1 do |row|
        index += 1

        next unless row[0]

        if row[headers.index 'Date de naissance']  
          date_de_naissance = Date.parse(row[headers.index 'Date de naissance'].to_s)
        else
          date_de_naissance = nil
        end

        etudiant = Etudiant
                    .where("lower(nom) = ? AND lower(prénom) = ? AND date_de_naissance = ?", 
                      row[headers.index 'NOM'].try(:strip).try(:downcase), 
                      row[headers.index 'Prénom'].try(:strip).try(:downcase),
                      date_de_naissance)
                    .first_or_initialize

        etudiant.formation_id = formation_id
        etudiant.workflow_state = workflow_state
        etudiant.civilité = row[headers.index 'Civilité'].try(:strip)
        etudiant.nom = row[headers.index 'NOM'].try(:strip).try(:upcase) 
        etudiant.nom_marital = row[headers.index 'NOM marital'].try(:strip).try(:upcase)
        etudiant.prénom = row[headers.index 'Prénom'].try(:strip)
        etudiant.email = row[headers.index 'Mail']
        etudiant.mobile = row[headers.index 'Téléphone']
        etudiant.date_de_naissance = date_de_naissance
        etudiant.lieu_naissance = row[headers.index 'Lieu de naissance']
        etudiant.pays_naissance = row[headers.index 'Pays de la ville de naissance'] 
        etudiant.nationalité = row[headers.index 'Nationalité']
        etudiant.adresse = row[headers.index 'Adresse']
        etudiant.cp = row[headers.index 'CP']
        etudiant.ville = row[headers.index 'Ville']
        etudiant.dernier_ets = row[headers.index 'Dernier établmt fréquenté']
        etudiant.dernier_diplôme = row[headers.index 'Dernier diplôme obtenu']
        etudiant.cat_diplôme = row[headers.index 'Catégorie "Science" diplôme']
        etudiant.num_sécu = row[headers.index 'Numéro Sécurité sociale']
        etudiant.num_apogée = row[headers.index 'Numéro Apogée étudiant']
        etudiant.poste_occupé = row[headers.index 'Poste occupé']
        etudiant.nom_entreprise = row[headers.index 'Nom Entreprise']
        etudiant.adresse_entreprise = row[headers.index 'Adresse entreprise']
        etudiant.cp_entreprise = row[headers.index 'CP entreprise']
        etudiant.ville_entreprise = row[headers.index 'Ville entreprise']
 
        # MAJ existant ? si l'id est égal à 0 => c'est une création
        msg = "ETUDIANT #{etudiant.new_record? ? 'NEW' : 'UPDATE'} => id:#{etudiant.id} changes:#{etudiant.changes}"

        if etudiant.valid? 
          etudiant.save if params[:save] == 'true'
        else
          msg << " || ERREURS: " + etudiant.errors.messages.map{|m| "#{m.first} => #{m.last}"}.join(',')
        end

        _etat = ( etudiant.valid? ? ImportLogLine.etats[:succès] : ImportLogLine.etats[:echec]) 
        log.import_log_lines.build(etat: _etat, num_ligne: index, message: msg)

        etudiant.valid? ? @importes += 1 : @errors += 1 
      end

      _etat = if @errors.zero?
        ImportLog.etats[:succès] 
      else 
        if @errors < @importes 
          ImportLog.etats[:warning]
        else
          ImportLog.etats[:echec]
        end
      end   
      
      log.update(etat: _etat, nbr_lignes: @importes + @errors, lignes_importees: @importes)
      log.update(message: (params[:save] == 'true' ? "Importation" : "Simulation") )
 
      if @errors > 0
        log.update(message: log.message + " | #{@errors} lignes rejetées !")
      end   
      log.save
      
      flash[:notice] = "L'importation a bien été exécutée"
      redirect_to import_logs_path
    else
      flash[:error] = "Manque le fichier source pour pouvoir lancer l'importation !"
      redirect_to action: 'import'
    end  

  end

  def swap_intervenant
    authorize :tool, :swap_intervenant?
  end

  def swap_intervenant_do
    authorize :tool, :swap_intervenant?
    
    unless params[:intervenant_from_id].blank? and params[:intervenant_to_id].blank?
    	
      # capture output
      @stream = capture_stdout do
        @importes = @errors = 0	

        @cours = Cour.where(intervenant_id:params[:intervenant_from_id])

        puts "#{@cours.count} cours à modifier"

        if (@cours.any? and params[:save] == 'true') 
          @cours.update_all(intervenant_id:params[:intervenant_to_id])
          puts "les cours ont été modifiés !"
        end 
        
        puts 
        puts "----------- Les modifications n'ont pas été enregistrées ! ---------------" unless params[:save] == 'true'
        puts

        puts "=" * 40
        puts "Lignes importées: #{@importes} | Lignes ignorées: #{@errors}"
        puts "=" * 40
      end

    else
      flash[:error] = "Manque les intervenants afin de lancer la modification !"
      redirect_to action: 'swap_intervenant'
    end  

  end

  def creation_cours
  end

  def creation_cours_do
	  @start_date = Date.civil(params[:cours]["start_date(1i)"].to_i,
                         	 params[:cours]["start_date(2i)"].to_i,
                         	 params[:cours]["start_date(3i)"].to_i)

	  @end_date = Date.civil(params[:cours]["end_date(1i)"].to_i,
                           params[:cours]["end_date(2i)"].to_i,
                           params[:cours]["end_date(3i)"].to_i)

    # Calcul le nombre de jours à traiter dans la période à traiter
  	@ndays = (@end_date - @start_date).to_i + 1 
	  salle_id = params[:salle_id]
    nom_cours = params[:nom]
    semaines = params[:semaines]

  	@cours_créés = @erreurs = 0

    @stream = capture_stdout do
      current_date = @start_date
      # Pour chaque jour de la période à traiter
      @ndays.times do
        # test jour
        wday = current_date.wday
        ok_jours = ((params[:lundi] && wday == 1) || (params[:mardi] && wday == 2) || 
                    (params[:mercredi] && wday == 3) || (params[:jeudi] && wday == 4) || 
                    (params[:vendredi] && wday == 5) || (params[:samedi] && wday == 6))
        # test semaine 
        ok_semaines = !params.include?('semaines') || (params[:semaines] && params[:semaines].include?(current_date.cweek.to_s))
        
        cours = []

        # création du cours type
        new_cours = Cour.new(formation_id: params[:formation_id], intervenant_id: params[:intervenant_id], nom: nom_cours, salle_id: salle_id)

        # cours du matin
        if params[:am]
          c = new_cours.dup
          c.duree = 3
          c.debut = Time.parse(current_date.to_s + " 9:00 UTC")
          c.fin = eval("c.debut + #{c.duree}.hour")
          cours << c
        end  

        # cours après midi
        if params[:pm]
          c = new_cours.dup
          c.duree = 3
          c.debut = Time.parse(current_date.to_s + " 13:00 UTC")
          c.fin = eval("c.debut + #{c.duree}.hour")
          cours << c
        end

        # cours du soir
        if params[:soir]
          c = new_cours.dup
          case params[:soir_params]
          when '1'
            c.duree = 3
            c.debut = Time.parse(current_date.to_s + " 19:00 UTC")
          when '2'  
            c.duree = 2
            c.debut = Time.parse(current_date.to_s + " 18:15 UTC")
          when '3'  
            c.duree = 2
            c.debut = Time.parse(current_date.to_s + " 20:15 UTC")
          end
          c.fin = eval("c.debut + #{c.duree}.hour")
          cours << c
        end
 
        if params[:other]
          # calcul de la date & heure de début et de fin  
          c = new_cours.dup
          c.duree = params[:duree]
          c.debut = Time.parse(current_date.to_s + " #{params[:cours]["start_date(4i)"]}:#{params[:cours]["start_date(5i)"]} UTC")
          c.fin = eval("c.debut + #{c.duree}.hour")
          cours << c
        end

        cours.each do | new_cours |  
          if ok_jours && ok_semaines
            msg = "#{I18n.l(new_cours.debut, format: :long)}-#{I18n.l(new_cours.fin, format: :heures_log)}"
            # création du cours
            if new_cours.valid?
              new_cours.save if params[:save] == 'true'
              puts "[OK] #{msg}"
              @cours_créés += 1
            else
              puts "[KO!] #{msg} => #{new_cours.errors.full_messages.join(', ')}"
              @erreurs += 1
            end
          end
        end
        
	  		current_date = current_date + 1.day
	  	end
	  	puts
		  puts "=" * 120
	  	puts "Création termninée | #{@cours_créés} cours #{'créé'.pluralize(@cours_créés)} | #{@erreurs} #{'erreur'.pluralize(@erreurs)}"
		  puts "=" * 120
	  	puts
	  	puts "--------!-!-! Les modifications n'ont pas été enregistrées !-!-!----------" unless params[:save] == 'true'
	  end  	
  end

  def export
  end

  def export_do
	  cours = Cour.includes(:formation, :intervenant, :salle, :audits).order(:debut)

    unless params[:start_date].blank? and params[:end_date].blank? 
      @start_date = Date.parse(params[:start_date])
      @end_date = Date.parse(params[:end_date])

      cours = cours.where("cours.debut BETWEEN DATE(?) AND DATE(?)", @start_date, @end_date)
    end

    unless params[:formation_id].blank?
      cours = cours.where(formation_id:params[:formation_id])
    end

    unless params[:intervenant_id].blank?
      intervenant_id = params[:intervenant_id]
      if params[:binome].present?
        cours = cours.where("intervenant_id = ? OR intervenant_binome_id = ?", intervenant_id, intervenant_id)
      else
        cours = cours.where(intervenant_id: intervenant_id)
      end
    end

    unless params[:etat].blank?
      cours = cours.where(etat:params[:etat])
    end

    book = Cour.generate_xls(cours, params[:binome].present?, true)  
    file_contents = StringIO.new
    book.write file_contents # => Now file_contents contains the rendered file output
    filename = "Export_Cours.xls"
    send_data file_contents.string.force_encoding('binary'), filename: filename 
  end

  def export_intervenants
  end

  def export_intervenants_do
    intervenants = Intervenant.all

    date_debut = params[:date_debut]
    date_fin = params[:date_fin]

    unless date_debut.blank? and date_fin.blank?
      intervenants_id = Cour.where("debut BETWEEN (?) AND (?)", date_debut, date_fin).pluck(:intervenant_id).uniq
      intervenants = intervenants.where(id: intervenants_id)
    end

    unless params[:status].blank?
      intervenants = intervenants.where("status = ?", params[:status])
    end

    book = Intervenant.generate_xls(intervenants, date_debut, date_fin)  
    file_contents = StringIO.new
    book.write file_contents # => Now file_contents contains the rendered file output
    filename = "Export_Intervenants_#{Date.today.to_s}.xls"
    send_data file_contents.string.force_encoding('binary'), filename: filename 
  end

  def etudiants
  end

  def export_etudiants_do
    etudiants = Etudiant.all

    unless params[:formation_id].blank?
      etudiants = etudiants.where(formation_id: params[:formation_id])
    end

    book = Etudiant.generate_xls(etudiants)  
    file_contents = StringIO.new
    book.write file_contents # => Now file_contents contains the rendered file output
    filename = "Export_Etudiants_#{Date.today.to_s}.xls"
    send_data file_contents.string.force_encoding('binary'), filename: filename 
  end

  def etats_services

    # quitter si l'utilisateur actuel n'est pas parmi les utilisateurs autorisés
    authorize :tool, :can_see_RHGroup_private_tool?

    @intervenants ||= []

    unless params[:start_date].blank? || params[:end_date].blank?
      @start_date = params[:start_date]
      @end_date = params[:end_date]
    else
      params[:start_date] ||= Date.today.at_beginning_of_month.last_month
      params[:end_date]   ||= Date.today.at_end_of_month.last_month
    end

    unless params[:status].blank?
      # Peupler la liste des intervenants ayant eu des cours en principal ou binome
      @cours =  Cour.réalisé.where("debut between ? and ?", @start_date, @end_date)
      ids = @cours.distinct(:intervenant_id).pluck(:intervenant_id)
      ids << @cours.distinct(:intervenant_binome_id).pluck(:intervenant_binome_id)

      # Ajouter les vacataires
      ids << Vacation
                .where("date between ? and ?", @start_date, @end_date)
                .distinct(:intervenant_id)
                .pluck(:intervenant_id)

      @intervenants = Intervenant.where(id: ids.flatten).where(status: params[:status])
      @intervenants_for_select = @intervenants
    end 

    unless params[:intervenant_id].blank? 
      @intervenants = Intervenant.where(id: params[:intervenant_id])
    end

    @cumul_hetd = @cumul_vacations = @cumul_resps = 0

    respond_to do |format|
      
      format.html

      format.csv do
        @csv_string = Cour.generate_etats_services_csv(@cours, @intervenants, @start_date, @end_date)
        filename = "Etats_de_services_#{Date.today.to_s}"
        response.headers['Content-Disposition'] = 'attachment; filename="' + filename + '.csv"'
        render "tools/etats_services.csv.erb"
      end

      format.xls do
        book = Cour.generate_etats_services_xls(@cours, @intervenants, @start_date, @end_date)
        file_contents = StringIO.new
        book.write file_contents # => Now file_contents contains the rendered file output
        filename = "Export_Cours.xls"
        send_data file_contents.string.force_encoding('binary'), filename: filename 
      end

      format.pdf do
        filename = "Etats_de_services_#{Date.today.to_s}"
        pdf = ExportPdf.new
        pdf.export_etats_de_services(@cours, @intervenants, @start_date, @end_date)

        send_data pdf.render,
            filename: filename.concat('.pdf'),
            type: 'application/pdf',
            disposition: 'inline'	

        # response.headers['Content-Disposition'] = 'attachment; filename="' + filename + '.pdf"'
        # render pdf: filename, :layout => 'pdf.html'
      end

    end
  end

  def audits
    @audits = Audited::Audit.order("id DESC")
    @types  = @audits.pluck(:auditable_type).uniq
    @actions= @audits.pluck(:action).uniq
    
    unless params[:start_date].blank? && params[:end_date].blank? 
      @audits = @audits.where("created_at BETWEEN (?) AND (?)", params[:start_date], params[:end_date])
    end

    unless params[:type].blank?
      @audits = @audits.where(auditable_type: params[:type])
    end

    unless params[:action_name].blank?
      @audits = @audits.where(action: params[:action_name])
    end

    unless params[:search].blank?
      @audits = @audits.where("audited_changes like ?", "%#{params[:search]}%")
    end

    unless params[:chgt_salle].blank?
      audit_chgt_salle_id = @audits.where("audited_changes like '%salle_id%'").map {|audit|
        audit.audited_changes['salle_id'] != nil ? audit.id : nil
      }.compact
      @audits = @audits.where(id: audit_chgt_salle_id) 
    end

    @audits = @audits.includes(:user).paginate(page: params[:page], per_page: 20)

    if params[:commit] == "Exporter"
      book = CustomAudit.generate_xls(@audits)  
      file_contents = StringIO.new
      book.write file_contents # => Now file_contents contains the rendered file output
      filename = "Export_Audits.xls"
      send_data file_contents.string.force_encoding('binary'), filename: filename
    end

  end

  def taux_occupation_jours
  end

  def taux_occupation_jours_do
    unless params[:start_date].blank? and params[:end_date].blank?
      @start_date = params[:start_date]
      @end_date = params[:end_date]
    else
      flash[:error] = "Il manque les dates..."
      redirect_to tools_taux_occupation_jours_path
      return
    end

    # Calcul du taux d'occupation
    #

    # salles concernées
    salles_dispo = Salle.salles_de_cours.count
    salles_dispo_samedi = Salle.salles_de_cours_du_samedi.count
    
    # amplitude 
    @nb_heures_journée = Salle.nb_heures_journée
    @nb_heures_soirée = Salle.nb_heures_soirée

    # nombre d'heures salles semaine
    heures_dispo_salles = [salles_dispo * @nb_heures_journée, salles_dispo_samedi * @nb_heures_soirée] 

    # nombre d'heures salles samedi
    heures_dispo_salles_samedi = [salles_dispo_samedi * @nb_heures_journée, salles_dispo_samedi * @nb_heures_soirée] 

    @nbr_jours = @total_jour = @total_soir = 0


    @results = []
    # pour chaque jour entre la date de début et la date de fin
    (@start_date.to_date..@end_date.to_date).each do |d|



      # on ne compte pas le dimanche ni les jours de fermetures
      if d.to_date.wday > 0 && !Fermeture.find_by(date:d.to_date)
        # cumul les heures de cours du jour et du soir
        nombre_heures_cours = [Cour.cumul_heures(d).first, Cour.cumul_heures(d).last]

        # calcul du taux d'occupation  
        if d.to_date.wday == 6 # le samedi, on ne comtpe que le batiment D
          taux_occupation = [(nombre_heures_cours.first * 100 / heures_dispo_salles_samedi.first),
                              (nombre_heures_cours.last * 100 / heures_dispo_salles_samedi.last)]
          @total_jour += taux_occupation.first
        else  
          taux_occupation = [(nombre_heures_cours.first * 100 / heures_dispo_salles.first), 
                              (nombre_heures_cours.last * 100 / heures_dispo_salles.last)]
          @total_jour += taux_occupation.first
          @total_soir += taux_occupation.last
        end  
        @nbr_jours += 1

        @results << [l(d.to_date, format: :long), taux_occupation.first.to_i, taux_occupation.last.to_i]
      end
    end   
  end

  def taux_occupation_salles
  end

  def taux_occupation_salles_do
    unless params[:start_date].blank? and params[:end_date].blank?
      @start_date = params[:start_date]
      @end_date = params[:end_date]
    else
      flash[:error] = "Il manque les dates..."
      redirect_to tools_taux_occupation_salles_path
      return
    end

    # Calcul du taux d'occupation par salles
    #
    
    # amplitude 
    @nb_heures_journée = Salle.nb_heures_journée
    @nb_heures_soirée = Salle.nb_heures_soirée

    # nombre de jours dans la période
    @nbr_jours = 0
    # nombre d'heures de disponibilité des salles 
    @nbr_heures_dispo_salle = 0
    # fait le cumul des jours et des heures de dispo salle
    (@start_date.to_date..@end_date.to_date).each do |d|
      # on ne compte pas le dimanche ni les jours de fermetures
      next if Fermeture.find_by(date:d.to_date)
      case d.to_date.wday 
          when 0    # dimanche
          when 1..5 # jours de la semaine 
            @nbr_jours += 1
            @nbr_heures_dispo_salle += (@nb_heures_journée + @nb_heures_soirée)
          when 6   # samedi
            @nbr_jours += 1
            @nbr_heures_dispo_salle += @nb_heures_journée
      end
    end 

    @results = {}
    Cour.where("debut between DATE(?) AND DATE(?) AND salle_id IS NOT NULL", @start_date, @end_date).each do | c |
      if Salle.salles_de_cours.include?(c.salle)
        salle = c.salle.nom
        if @results[salle]
          @results[salle] += c.duree.to_f
        else
          @results[salle] = c.duree.to_f
        end
      end
    end
  end

  def nouvelle_saison

    @years ||= ['2018/2019','2019/2020','2020/2021','2021/2022','2022/2023','2023/2024','2024/2025']

    unless params[:saison].blank?
      @formations = Formation.where(hors_catalogue:false)
                             .where("nom like ?", "%#{params[:saison]}%")
      
      case params[:saison]
      when @years[0]
        @date_debut = Date.parse('2018-09-03')
        @date_fin = Date.parse('2019-07-15')
      when @years[1]
        @date_debut = Date.parse('2019-09-02')
        @date_fin = Date.parse('2020-07-15')
      else
        annee_debut = params[:saison].split('/').first
        annee_fin = params[:saison].split('/').last
        @date_debut = Date.parse(annee_debut + '-08-30')
        @date_fin = Date.parse(annee_fin + '-07-15')
      end
    end

    unless params[:formation_id].blank?
      @formation_id = params[:formation_id]
    end

    if (@date_debut and @date_fin) and @formation_id
      @jours = (@date_debut..@date_fin).select{|j| j.wday == 1}
    end

  end

  def nouvelle_saison_create
    _date_debut = Date.parse(params[:date_debut])
    _date_fin = Date.parse(params[:date_fin])
    _formation = Formation.find(params[:formation_id])
    _intervenant = Intervenant.find(445) # A CONFIRMER
    _semaines = params[:semaine].try(:keys)
    _errors = 0
    _jours = []

    if _semaines
      (_date_debut.._date_fin).each do |j|
        if _semaines.include?(j.cweek.to_s)
          wday = j.wday
          ok_jours = ((params[:lundi] && wday == 1) || (params[:mardi] && wday == 2) || 
                      (params[:mercredi] && wday == 3) || (params[:jeudi] && wday == 4) || 
                      (params[:vendredi] && wday == 5) || (params[:samedi] && wday == 6))
          if ok_jours
            _jours << j
            unless création_cours(_formation, j, _intervenant, true, true)
              _errors = _errors + 1 
            end
          end
        end  
      end
    end

    if _errors.zero?
      flash[:notice] = "#{_jours.count} cours créés"
    else
      flash[:error] = "#{_jours.count} cours créés + #{_errors} erreurs (ces cours n'ont pas été créés) !"
    end  
    redirect_to cours_path(formation_id: _formation, etat: Cour.etats[:plannifié])

  end

  def création_cours(formation, jour, intervenant, am, pm)
    new_cours = Cour.new(formation: formation, intervenant: intervenant)
    if am || pm
      if am
        new_cours.duree = 3
        new_cours.debut = Time.parse(jour.to_s + " 9:00 UTC")
        new_cours.fin = eval("new_cours.debut + #{new_cours.duree}.hour")
      elsif pm
        new_cours.duree = 3
        new_cours.debut = Time.parse(jour.to_s + " 13:00 UTC")
        new_cours.fin = eval("new_cours.debut + #{new_cours.duree}.hour")
      end
      # création du cours de l'après midi si besoin
      if (am && pm)
        new_cours_pm = Cour.new(formation: formation, intervenant: intervenant)
        new_cours_pm.duree = 3
        new_cours_pm.debut = Time.parse(jour.to_s + " 13:00 UTC")
        new_cours_pm.fin = eval("new_cours_pm.debut + #{new_cours_pm.duree}.hour")
      end  
    else
      # calcul de la date & heure de début et de fin  
      new_cours.duree = duree
      new_cours.debut = Time.parse(jour.to_s + " #{params[:cours]["start_date(4i)"]}:#{params[:cours]["start_date(5i)"]} UTC")
      new_cours.fin = eval("new_cours.debut + #{new_cours.duree}.hour")
    end

    _ok = true  
    if new_cours.valid?
      new_cours.save
    else
      _ok = false 
    end

    if new_cours_pm
      if new_cours_pm.valid?
        new_cours_pm.save 
      else
        _ok = false
      end
    end
    
    return _ok
  end

  def notifier_intervenants
  end

  def notifier_intervenants_do
    require 'rake'

    Rake::Task.clear # necessary to avoid tasks being loaded several times in dev mode
    Rails.application.load_tasks # providing your application name is 'sample'
      
    # capture output
    @stdout_stream = capture_stdout do
      Rake::Task['cours:envoyer_liste_cours'].reenable # in case you're going to invoke the same task second time.
      Rake::Task['cours:envoyer_liste_cours'].invoke(params[:draft].present?)
    end
  end  
  
end
