# encoding: UTF-8

class AddExtraFieldsToUser < ActiveRecord::Migration
  def change
    add_column :users, :nom, :string
    add_column :users, :prénom, :string
    add_column :users, :mobile, :string
  end
end
