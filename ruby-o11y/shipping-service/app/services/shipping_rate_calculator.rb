class ShippingRateCalculator
  TRACER = OpenTelemetry.tracer_provider.tracer("shipping-service")

  CARRIERS = {
    ground: {
      name: "Ground Shipping",
      carrier: "USPS",
      min_days: 5,
      max_days: 7,
      base_rate: 5.99
    },
    express: {
      name: "Express Shipping",
      carrier: "UPS",
      min_days: 2,
      max_days: 3,
      base_rate: 12.99
    },
    overnight: {
      name: "Overnight Shipping",
      carrier: "FedEx",
      min_days: 1,
      max_days: 1,
      base_rate: 24.99
    }
  }.freeze

  def self.calculate(origin:, destination:, package:)
    TRACER.in_span("calculate rates", attributes: {
      "shipping.origin.zip" => origin[:zip].to_s,
      "shipping.destination.zip" => destination[:zip].to_s,
      "shipping.package.weight" => package[:weight].to_f
    }) do |span|
      weight = package[:weight].to_f
      sleep(rand(0.05..0.15))

      rates = CARRIERS.map do |key, carrier|
        rate = compute_rate(carrier[:base_rate], weight, key)
        delivery_date = compute_delivery_date(carrier[:min_days], carrier[:max_days])

        {
          id: "#{key}_#{SecureRandom.hex(4)}",
          service: carrier[:name],
          carrier: carrier[:carrier],
          rate: rate.round(2),
          currency: "USD",
          estimated_delivery: delivery_date.iso8601,
          delivery_days: (delivery_date.to_date - Date.current).to_i,
          guaranteed: key == :overnight
        }
      end

      span.set_attribute("shipping.rates.count", rates.size)
      rates
    end
  end

  def self.compute_rate(base_rate, weight, tier)
    TRACER.in_span("compute rate", attributes: {
      "shipping.carrier.tier" => tier.to_s
    }) do |span|
      weight_surcharge = weight * case tier
                                  when :ground then 0.50
                                  when :express then 0.75
                                  when :overnight then 1.25
                                  end
      jitter = rand(-0.50..1.50)
      rate = base_rate + weight_surcharge + jitter
      span.set_attribute("shipping.rate.amount", rate.round(2))
      rate
    end
  end

  def self.compute_delivery_date(min_days, max_days)
    days = rand(min_days..max_days)
    days.business_days_from_now
  end

  private_class_method :compute_rate, :compute_delivery_date

  # Simple business day calculation
  def self.business_days_from_now(days)
    date = Date.current
    days.times do
      date += 1
      date += 1 while date.saturday? || date.sunday?
    end
    date.to_time
  end
end

# Patch Integer for convenience
class Integer
  def business_days_from_now
    ShippingRateCalculator.send(:business_days_from_now, self)
  end
end
