require 'spec_helper'

module OpenFoodNetwork
  describe ProductsAndInventoryReport do
    context "As a site admin" do
      let(:user) do
        user = create(:user)
        user.spree_roles << Spree::Role.find_or_create_by_name!("admin")
        user
      end
      subject do
        ProductsAndInventoryReport.new user, {}, true
      end

      it "Should return headers" do
        expect(subject.header).to eq([
          "Supplier",
          "Producer Suburb",
          "Product",
          "Product Properties",
          "Taxons",
          "Variant Value",
          "Price",
          "Group Buy Unit Quantity",
          "Amount",
          "SKU"
        ])
      end

      it "should build a table from a list of variants" do
        variant = double(:variant, sku: "sku",
                        full_name: "Variant Name",
                        count_on_hand: 10,
                        price: 100)
        allow(variant).to receive_message_chain(:product, :supplier, :name).and_return("Supplier")
        allow(variant).to receive_message_chain(:product, :supplier, :address, :city).and_return("A city")
        allow(variant).to receive_message_chain(:product, :name).and_return("Product Name")
        allow(variant).to receive_message_chain(:product, :properties).and_return [double(name: "property1"), double(name: "property2")]
        allow(variant).to receive_message_chain(:product, :taxons).and_return [double(name: "taxon1"), double(name: "taxon2")]
        allow(variant).to receive_message_chain(:product, :group_buy_unit_size).and_return(21)
        allow(subject).to receive(:variants).and_return [variant]

        expect(subject.table).to eq([[
          "Supplier",
          "A city",
          "Product Name",
          "property1, property2",
          "taxon1, taxon2",
          "Variant Name",
          100,
          21,
          "",
          "sku"
        ]])
      end

      it "fetches variants for some params" do
        expect(subject).to receive(:child_variants).and_return ["children"]
        expect(subject).to receive(:filter).with(['children']).and_return ["filter_children"]
        expect(subject.variants).to eq(["filter_children"])
      end
    end

    context "As an enterprise user" do
      let(:supplier) { create(:supplier_enterprise) }
      let(:enterprise_user) do
        user = create(:user)
        user.enterprise_roles.create(enterprise: supplier)
        user.spree_roles = []
        user.save!
        user
      end

      subject do
        ProductsAndInventoryReport.new enterprise_user, {}, true
      end

      describe "fetching child variants" do
        it "returns some variants" do
          product1 = create(:simple_product, supplier: supplier)
          variant_1 = product1.variants.first
          variant_2 = create(:variant, product: product1)

          expect(subject.child_variants).to match_array [variant_1, variant_2]
        end

        it "should only return variants managed by the user" do
          product1 = create(:simple_product, supplier: create(:supplier_enterprise))
          product2 = create(:simple_product, supplier: supplier)
          variant_1 = product1.variants.first
          variant_2 = product2.variants.first

          expect(subject.child_variants).to eq([variant_2])
        end
      end

      describe "Filtering variants" do
        let(:variants) { Spree::Variant.scoped.joins(:product).where(is_master: false) }
        it "should return unfiltered variants sans-params" do
          product1 = create(:simple_product, supplier: supplier)
          product2 = create(:simple_product, supplier: supplier)

          expect(subject.filter(Spree::Variant.scoped)).to match_array [product1.master, product1.variants.first, product2.master, product2.variants.first]
        end
        it "should filter deleted products" do
          product1 = create(:simple_product, supplier: supplier)
          product2 = create(:simple_product, supplier: supplier)
          product2.destroy
          expect(subject.filter(Spree::Variant.scoped)).to match_array [product1.master, product1.variants.first]
        end
        describe "based on report type" do
          it "returns only variants on hand" do
            product1 = create(:simple_product, supplier: supplier, on_hand: 99)
            product2 = create(:simple_product, supplier: supplier, on_hand: 0)

            allow(subject).to receive(:params).and_return(report_type: 'inventory')
            expect(subject.filter(variants)).to eq([product1.variants.first])
          end
        end
        it "filters to a specific supplier" do
          supplier2 = create(:supplier_enterprise)
          product1 = create(:simple_product, supplier: supplier)
          product2 = create(:simple_product, supplier: supplier2)

          allow(subject).to receive(:params).and_return(supplier_id: supplier.id)
          expect(subject.filter(variants)).to eq([product1.variants.first])
        end
        it "filters to a specific distributor" do
          distributor = create(:distributor_enterprise)
          product1 = create(:simple_product, supplier: supplier)
          product2 = create(:simple_product, supplier: supplier)
          order_cycle = create(:simple_order_cycle, suppliers: [supplier], distributors: [distributor], variants: [product2.variants.first])

          allow(subject).to receive(:params).and_return(distributor_id: distributor.id)
          expect(subject.filter(variants)).to eq([product2.variants.first])
        end

        it "ignores variant overrides without filter" do
          distributor = create(:distributor_enterprise)
          product = create(:simple_product, supplier: supplier, price: 5)
          variant = product.variants.first
          order_cycle = create(:simple_order_cycle, suppliers: [supplier], distributors: [distributor], variants: [product.variants.first])
          create(:variant_override, hub: distributor, variant: variant, price: 2)

          result = subject.filter(variants)

          expect(result.first.price).to eq 5
        end

        it "considers variant overrides with distributor" do
          distributor = create(:distributor_enterprise)
          product = create(:simple_product, supplier: supplier, price: 5)
          variant = product.variants.first
          order_cycle = create(:simple_order_cycle, suppliers: [supplier], distributors: [distributor], variants: [product.variants.first])
          create(:variant_override, hub: distributor, variant: variant, price: 2)

          allow(subject).to receive(:params).and_return(distributor_id: distributor.id)
          result = subject.filter(variants)

          expect(result.first.price).to eq 2
        end

        it "filters to a specific order cycle" do
          distributor = create(:distributor_enterprise)
          product1 = create(:simple_product, supplier: supplier)
          product2 = create(:simple_product, supplier: supplier)
          order_cycle = create(:simple_order_cycle, suppliers: [supplier], distributors: [distributor], variants: [product1.variants.first])

          allow(subject).to receive(:params).and_return(order_cycle_id: order_cycle.id)
          expect(subject.filter(variants)).to eq([product1.variants.first])
        end

        it "should do all the filters at once" do
          distributor = create(:distributor_enterprise)
          product1 = create(:simple_product, supplier: supplier)
          product2 = create(:simple_product, supplier: supplier)
          order_cycle = create(:simple_order_cycle, suppliers: [supplier], distributors: [distributor], variants: [product1.variants.first])

          allow(subject).to receive(:params).and_return(
            order_cycle_id: order_cycle.id,
            supplier_id: supplier.id,
            distributor_id: distributor.id,
            report_type: 'inventory')
          subject.filter(variants)
        end
      end

      describe "fetching SKU for a variant" do
        let(:variant) { create(:variant) }
        let(:product) { variant.product }

        before { product.update_attribute(:sku, "Product SKU") }

        context "when the variant has an SKU set" do
          before { variant.update_attribute(:sku, "Variant SKU") }
          it "returns it" do
            expect(subject.send(:sku_for, variant)).to eq "Variant SKU"
          end
        end

        context "when the variant has bo SKU set" do
          before { variant.update_attribute(:sku, "") }

          it "returns the product's SKU" do
            expect(subject.send(:sku_for, variant)).to eq "Product SKU"
          end
        end
      end
    end
  end
end
