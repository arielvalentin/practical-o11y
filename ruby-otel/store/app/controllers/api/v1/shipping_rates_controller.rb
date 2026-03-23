module Api
  module V1
    class ShippingRatesController < ActionController::API
      def create
        origin = params.require(:origin).permit(:zip, :city, :state, :country)
        destination = params.require(:destination).permit(:zip, :city, :state, :country)
        package = params.require(:package).permit(:weight, :length, :width, :height)

        result = ShippingClient.new.calculate_rates(
          origin: origin.to_h,
          destination: destination.to_h,
          package: package.to_h
        )

        render json: result
      rescue ShippingClient::ShippingError => e
        render json: { error: e.message }, status: :service_unavailable
      end
    end
  end
end
