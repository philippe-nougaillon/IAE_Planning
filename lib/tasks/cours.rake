# ENCODING: UTF-8

namespace :cours do

  desc "TODO"
  task update_duree: :environment do
	Cour.where(duree:0).each do |cours|
	  	cours.update_attributes(duree:(cours.fin - cours.debut) / 60 / 60)
  	end
  end

  desc "Passer les cours J - 1 en état Confirmé vers l'état Réalisé"
  task update_etat_realises: :environment do
      Cour.where("DATE(debut)=?", Date.today - 1.day)
          .where(etat: Cour.etats[:confirmé])
          .update_all(etat: Cour.etats[:réalisé])
  end

  desc "Envoyer la liste des cours aux intervenants" 
  task :envoyer_liste_cours, [:draft] => :environment do |task, args|

    # Quitter si nous ne sommes pas le 24 du mois et pas en draftmode 
    next if Date.today.day != 24 && !args.draft 

    puts "MODE DRAFT" if args.draft

    start_day = Date.today.beginning_of_month + 1.month
    end_day   = start_day.end_of_month + 1.day 
    puts "Période du #{I18n.l start_day} au #{I18n.l end_day}"

    envoyes = 0

    Intervenant.all.each do |intervenant| 

      cours = Cour.where("debut BETWEEN (?) AND (?)", start_day, end_day)
                   .where(etat: Cour.etats.values_at(:planifié, :confirmé))
                   .where.not(intervenant_id: 445)
                   .where("intervenant_id = ? OR intervenant_binome_id = ?", intervenant.id, intervenant.id)

      if cours.any?
        puts "#{intervenant.nom_prenom} (##{intervenant.id})" 
                      
        liste_des_cours_a_envoyer = []
        liste_des_gestionnaires = {}

        cours.each do |c|
          intitulé_cours = "#{I18n.l(c.debut.to_date, format: :day)} #{I18n.l(c.debut.to_date)} #{I18n.l(c.debut, format: :heures_min)}-#{I18n.l(c.fin, format: :heures_min)} #{c.try(:formation).try(:nom)}/#{c.nom_ou_ue}"
          liste_des_cours_a_envoyer << intitulé_cours
          if c.formation
            liste_des_gestionnaires[c.formation.nom] = (c.formation.courriel ? c.formation.courriel : c.formation.try(:user).try(:email))
          end
        end
        puts "#{liste_des_cours_a_envoyer.count} cours à envoyer: #{liste_des_cours_a_envoyer}"  

        liste_des_gestionnaires.each do | formation, gest |
          puts "Gestionnaire #{formation} = #{gest}"
        end

        envoyes += 1 if envoyer_liste_cours_a_intervenant(args.draft, start_day, end_day, intervenant, cours, liste_des_gestionnaires) 

        puts "#-" * 50
      end 
    end

    puts "* #{envoyes} mail(s) envoyé(s) *"

    # Envoyer le récap à Barbara et à moi
    unless args.draft
      UserMailer
        .notifier_fin_envoi_prochains_cours(envoyes)
        .deliver_now
    end 

  end

  def envoyer_liste_cours_a_intervenant(draft, debut, fin, intervenant, cours, gestionnaires)
    if !intervenant.email.blank? && intervenant.email != '?'
      puts "OK => Planning envoyé à: #{intervenant.email}"

      unless draft
        IntervenantMailer
            .notifier_cours(debut, fin, intervenant, cours, gestionnaires)
            .deliver_now
      end

      return true
    else
      puts "!KO => Manque l'adresse email de '#{intervenant.nom_prenom}' (= #{intervenant.email})" 

      return false
    end
  end

end
