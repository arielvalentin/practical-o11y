module Api
  module V1
    class RecommendationsController < ApplicationController
      def index
        product_id = params.require(:product_id)
        limit = (params[:limit] || 4).to_i.clamp(1, 20)

        recommendations = RecommendationEngine.recommend(
          product_id: product_id,
          limit: limit
        )

        render json: {
          product_id: product_id,
          recommendations: recommendations,
          generated_at: Time.current.iso8601
        }
      rescue ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end
