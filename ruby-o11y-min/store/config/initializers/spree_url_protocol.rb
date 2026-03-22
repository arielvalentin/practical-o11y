# Override Spree::Store#formatted_url to respect SPREE_URL_PROTOCOL env var.
# In production, Spree hardcodes HTTPS. For local Docker development in
# production mode, we need HTTP with the correct port.
if ENV["SPREE_URL_PROTOCOL"] == "http"
  Rails.application.config.after_initialize do
    Spree::Store.class_eval do
      def formatted_url
        @formatted_url = nil # bust memoization

        clean_url = url.to_s.sub(%r{^https?://}, "")
        host, port = clean_url.split(":")

        if port.present?
          URI::HTTP.build(host: host, port: port.to_i).to_s
        else
          URI::HTTP.build(host: host).to_s
        end
      end
    end
  end
end
