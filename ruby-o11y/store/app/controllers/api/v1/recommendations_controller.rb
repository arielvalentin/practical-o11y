module Api
  module V1
    class RecommendationsController < ActionController::API
      def index
        product_id = params.require(:product_id)
        limit = params.fetch(:limit, 4).to_i

        result = RecommendationClient.new.recommendations_for(
          product_id: product_id,
          limit: limit
        )

        render json: result
      rescue RecommendationClient::RecommendationError => e
        render json: { error: e.message }, status: :service_unavailable
      end
    end
  end
end
