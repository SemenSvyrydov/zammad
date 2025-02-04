# Copyright (C) 2012-2022 Zammad Foundation, https://zammad-foundation.org/

class ChecksKbClientNotificationJob < ApplicationJob
  include HasActiveJobLock

  def lock_key
    # "ChecksKbClientNotificationJob/KnowledgeBase::Answer/42"
    "#{self.class.name}/#{arguments[0]}/#{arguments[1]}"
  end

  def perform(klass_name, object_id)
    object = klass_name.constantize.find_by(id: object_id)
    return if object.blank?

    level = needs_editor?(object) ? 'editor' : '*'

    payload = {
      event: 'kb_data_changed',
      data:  build_data(object, event)
    }

    users_for(level).each { |user| notify(user, payload) }
  end

  def build_data(object, event)
    timestamp = event == :destroy ? Time.zone.now : object.updated_at
    url       = event == :destroy ? nil           : object.try(:api_url)

    {
      class:     object.class.to_s,
      event:     event,
      id:        object.id,
      timestamp: timestamp,
      url:       url
    }
  end

  def needs_editor?(object)
    case object
    when KnowledgeBase::Answer
      object.can_be_published_aasm.draft?
    when KnowledgeBase::Category
      !object.internal_content?
    else
      false
    end
  end

  def notify(user, payload)
    PushMessages.send_to(user.id, payload)
  end

  def users_for(permission_suffix)
    Sessions
      .sessions
      .filter_map { |client_id| Sessions.get(client_id)&.dig(:user, 'id') }
      .filter_map { |user_id| User.find_by(id: user_id) }
      .select { |user| user.permissions? "knowledge_base.#{permission_suffix}" }
  end
end
