module Api
  module V1
    class RatesController < ApplicationController
      def create
        origin = params.require(:origin).permit(:zip, :city, :state, :country)
        destination = params.require(:destination).permit(:zip, :city, :state, :country)
        package = params.require(:package).permit(:weight, :length, :width, :height)

        rates = ShippingRateCalculator.calculate(
          origin: origin.to_h,
          destination: destination.to_h,
          package: package.to_h
        )

        render json: { rates: rates, calculated_at: Time.current.iso8601 }
      rescue ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end
