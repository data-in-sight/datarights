# == Schema Information
#
# Table name: access_requests
#
#  id                 :integer          not null, primary key
#  organization_id    :integer
#  user_id            :integer
#  meta_data          :jsonb
#  sent_date          :datetime
#  data_received_date :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  campaign_id        :integer
#  suggested_text     :text
#  final_text         :text
#

class AccessRequest < ApplicationRecord
  belongs_to :organization
  belongs_to :user
  belongs_to :campaign
  has_one :workflow, dependent: :destroy
  has_many :answers, as: :answerable, dependent: :destroy
  has_many :tags, :as => :tagable, dependent: :destroy
  has_many :comments, :as => :commentable, dependent: :destroy
  before_save :update_related_caches, if: :campaign_id_changed?
  before_destroy :update_related_caches
  after_create :create_workflow

  attr_accessor :expanded
  attr_accessor :standard
  attr_accessor :sector_id
  attr_accessor :template_version_id

  validates :user, :organization, :campaign, presence: true

  def context_value
    { 'id' => id, 'data_received_date' => self.data_received_date, 'sent_date' => self.sent_date }
  end

  def update_related_caches
    if self.changes.include?('campaign_id')
      old_campaign_id = self.changes['campaign_id'].first
      Rails.cache.delete("campaign/#{old_campaign_id}/count_of_access_requests") if old_campaign_id
    end
    Rails.cache.delete("campaign/#{self.campaign_id}/count_of_access_requests") if campaign
    Rails.cache.delete("user/#{self.user_id}/campaign/#{self.campaign_id}/count_of_access_requests") if campaign
  end

  def create_workflow
    wf = Workflow.new
    wf.workflow_type_version = self.campaign.workflow_type.current_version
    wf.access_request = self
    wf.save!
  end

  def self.available_templates(template_type, organization)
    return [] unless organization.sector

    if template_type.class == :String
      template_type = template_type.to_sym
    end

    return [] unless Template.template_types.include?(template_type)

    active_templates = organization.sector.templates.joins(:template_versions).where(:templates => {template_type: template_type}, :template_versions => {:active => true})
    return [] if active_templates.blank?

    template_versions = []

    active_templates.each do |template|
      template.template_versions.where(:active => true).each do |tv|
        template_versions << tv unless template_versions.include?(tv)
      end
    end

    template_versions
  end

  def get_rendered_template(template_type, template_version=nil)
    @rendered_template ||= AccessRequest.get_rendered_template(template_type, self.user, self.campaign, self.organization, self, template_version)
  end

  def self.get_rendered_template(template_type, user, campaign, organization, access_request=nil, template_version=nil)
    return nil unless organization.sector

    if template_type.class == :String
      template_type = template_type.to_sym
    end

    unless Template.template_types.include?(template_type)
      return ''
    end

    active_templates = organization.sector.templates.joins(:template_versions).where(:templates => {template_type: template_type}, :template_versions => {:active => true})
    return nil if active_templates.blank?

    template_versions = []
    active_templates.each do |t|
      t.template_versions.where(:active => true).each do |tv|
        template_versions << tv unless template_versions.include?(tv)
      end
    end

    result = nil
    if template_version
      result = template_versions.detect {|t| t.id == template_version.id}
    else
      result = template_versions.first
    end

    if result
      context = TemplateContext.new
      if access_request && access_request&.workflow
        context.access_request = access_request
        context.workflow = access_request.workflow
      end
      context.campaign = campaign
      context.user = user
      context.organization = organization
      result.render(context)
    else
      nil
    end
  end
end
