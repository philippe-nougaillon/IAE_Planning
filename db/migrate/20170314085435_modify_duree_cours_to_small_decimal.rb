class ModifyDureeCoursToSmallDecimal < ActiveRecord::Migration
  def change
  	change_column :cours, :duree, :decimal, precision: 4, scale: 2, default:0.0
  end
end
