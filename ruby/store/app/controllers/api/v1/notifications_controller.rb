module Api
  module V1
    class NotificationsController < ActionController::API
      def create
        notification_params = params.require(:notification).permit(:type, :recipient, :subject, payload: {})

        result = NotificationClient.new.send_notification(
          type: notification_params[:type],
          recipient: notification_params[:recipient],
          subject: notification_params[:subject],
          payload: notification_params[:payload]&.to_h || {}
        )

        render json: result, status: :accepted
      rescue NotificationClient::NotificationError => e
        render json: { error: e.message }, status: :service_unavailable
      end
    end
  end
end
