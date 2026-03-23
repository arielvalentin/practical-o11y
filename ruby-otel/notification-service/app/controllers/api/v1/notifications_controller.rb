module Api
  module V1
    class NotificationsController < ApplicationController
      def create
        notification_params = params.require(:notification).permit(:type, :recipient, :subject, payload: {})

        result = NotificationDispatcher.dispatch(
          type: notification_params[:type],
          recipient: notification_params[:recipient],
          subject: notification_params[:subject],
          payload: notification_params[:payload]&.to_h || {}
        )

        render json: result, status: :accepted
      rescue ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def index
        notifications = Notification.order(created_at: :desc).limit(params.fetch(:limit, 20).to_i)
        render json: { notifications: notifications }
      end
    end
  end
end
