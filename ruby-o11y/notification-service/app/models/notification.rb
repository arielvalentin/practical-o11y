class Notification < ApplicationRecord
  validates :notification_type, :recipient, :status, presence: true

  enum :status, {
    pending: "pending",
    processing: "processing",
    delivered: "delivered",
    failed: "failed"
  }

  scope :recent, -> { order(created_at: :desc) }
end
