# == Schema Information
#
# Table name: campaigns
#
#  id                   :integer          not null, primary key
#  name                 :string
#  short_description    :string
#  expanded_description :text
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#

class Campaign < ApplicationRecord
  has_and_belongs_to_many :organizations
  has_many :access_requests
  has_and_belongs_to_many :questions
  has_many :answers, as: :answerable
  has_and_belongs_to_many :users

  def context_value
    result = { 'name' => name.blank? ? '' : name }
    result['short_description']  = short_description if short_description
    result['expanded_description'] = expanded_description if expanded_description
    result
  end

end
