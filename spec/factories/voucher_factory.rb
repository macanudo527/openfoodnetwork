# frozen_string_literal: true

FactoryBot.define do
  factory :voucher, class: Voucher do
    code { "new_code" }
    enterprise { build(:distributor_enterprise) }
    amount { 10 }
  end

  factory :voucher_flat_rate, parent: :voucher, class: Vouchers::FlatRate do
    amount { 15 }
  end

  factory :voucher_percentage_rate, parent: :voucher, class: Vouchers::PercentageRate do
    amount { rand(1..100) }
  end

  factory :vine_voucher, parent: :voucher, class: Vouchers::Vine do
    amount { 20 }
    external_voucher_id { SecureRandom.uuid }
    external_voucher_set_id { SecureRandom.uuid }
  end
end
