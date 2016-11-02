# My first rspec script

require 'spec_helper'
require_relative '../pos'

def silenced
  $stdout = StringIO.new
  yield
ensure
  $stdout = STDOUT
end

describe POS do
  context 'instantiated with no parameters' do

    it 'has default values' do
      expect(subject.ccy).to eql "gbp"
      expect(subject.ref).to eql 0
      expect(subject.bill_list).to be_an(Hash).and be_empty
      expect(subject.system_total).to eql Money.new(0, "gbp")
    end
  end

  context 'instantiated with parameters' do
    let (:currency) { "usd"}
    let (:new_pos)  { POS.new(currency, enforce_locales:true, ref_start:70) }

    it 'holds user values' do
      expect(new_pos.ccy).to eql currency
      expect(new_pos.ref).to eql 69
      expect(new_pos.bill_list).to be_empty
      expect(new_pos.system_total).to eql Money.new(0, currency)
    end
  end

  describe '#new_bill' do
    let (:bill) { subject.new_bill }

    it 'will create a bill object' do
      expect(bill).to be_an_instance_of Bill
    end
  end

  describe '#new_item' do
    let (:item) { subject.new_item('item', 0) }

    it 'will create an item object' do
      expect(item).to be_an_instance_of Item
    end
  end
end

describe Item do
  let (:pos)  { POS.new }
  let (:item) { pos.new_item('test', 0) }

  context 'instantiated with no keywords' do
    it 'has default values' do
      expect(item.name).to eql :test
      expect(item.price).to eql Money.new(0, pos.ccy)
      expect(item.tax).to eql 0.0
      expect(item.discount).to be false
      expect(item.price_include_vat).to be true
      expect(item.tags).to be_an(Array).and be_empty
    end
  end

  context 'instantiated with user defined keywords' do
    let (:item) do
      pos.new_item('test', 5.50, discount:[1, 1, 0],
                                 tax:20,
                                 tags:['Meat', 'Longlife'],
                                 price_include_vat:false)
    end

    it 'holds user values' do
      expect(item.name).to eql :test
      expect(item.price).to eql Money.new(550, pos.ccy)
      expect(item.tax).to eql 20.0
      expect(item.discount).to eql [1, 1, 0]
      expect(item.tags).to eql([:meat, :longlife])
      expect(item.price_include_vat).to be false
    end
  end

  describe '#tosymbol' do
    let (:case1) { "Hello World" }
    let (:case2) { 31415 }

    it 'converts item to a downcased valid symbol' do
      expect(item.tosymbol(case1)).to eql :hello_world
      expect(item.tosymbol(case2)).to eql :"31415"
    end

    it 'converts new tags to symbols' do
      item.tags<<case1
      item.tags<<case2
      expect(item.tags[-2]).to eql :hello_world
      expect(item.tags[-1]).to eql :"31415"
    end
  end

  describe '#price=' do
    let (:ccy_multiplier) { Money::Currency.table[pos.ccy.to_sym][:subunit_to_unit] }
    context 'when given a money object' do
      it 'will ensure the currency is the same as the POS objects' do
        item.price = Money.new(300, 'zwd')
        expect(item.price).to eql Money.new(300, pos.ccy)
      end
    end

    context 'when given a numeric value' do
      it 'will turn it into an equivalent money object' do
        item.price = 9
        expect(item.price).to eql Money.new(9 * ccy_multiplier, pos.ccy)

        item.price = 3.55
        expect(item.price).to eql Money.new(3.55 * ccy_multiplier, pos.ccy)
      end
    end

    context 'when given an invalid value' do
      it 'will make price a naught value money object' do
        silenced { item.price = 'Hello World'; nil }
        expect(item.price).to eql Money.new(0, pos.ccy)
      end
    end
  end

  describe '#tax=' do
    context 'when given an integer' do
      it 'will turn it into a float' do
        item.tax = 13
        expect(item.tax).to eql 13.0
      end
    end

    context 'when given an invalid value' do
      it 'will make tax naught' do
        silenced { item.tax = [1,2,3] }
        expect(item.tax).to eql 0.0
      end
    end
  end

  describe '#discount=' do
    context 'when passed an invalid value' do
      let (:invalids) { ['Banana', [1, 1, 1, 0], [1, 2.5, 5], ['a', 4, 1]] }
      let (:valid)    { [1, 1, 0] }

      it 'will set discount to false' do
        invalids.each do |invalid|
          silenced { item.discount = invalid }
          expect(item.discount).to be false

          item.discount = valid
        end
      end
    end
  end

  describe '#tags=' do
    context 'when given an array' do
      it 'will turn every element of the array into a symbol' do
        item.tags = ["Hello World", 56, 99.99]
        expect(item.tags).to all( be_an(Symbol) )
      end
    end

    context 'when given a single value' do
      it 'will make the value a symbol, and put it in an array' do
        item.tags = "Test"
        expect(item.tags).to eql [:test]
      end
    end
  end

  describe "#price_include_vat=" do
    context 'when passed an invalid value' do
      it 'will set price_include_vat to true' do
        item.price_include_vat = false
        silenced { item.price_include_vat = 'Banana' }
        expect(item.price_include_vat).to be true
      end
    end
  end
end

describe Bill do
  let (:pos) { POS.new }
  let (:zero) { Money.new(0, pos.ccy) }
  subject { pos.new_bill }

  context 'instantiated' do
    it 'has nil balances' do
      expect(subject.subtotal).to eql zero
      expect(subject.tax).to eql      zero
      expect(subject.discount).to eql zero
    end

    it 'has the latest ref' do
      expect(subject.bill_ref).to eql pos.ref
    end

    it 'has no items' do
      expect(subject.items).to be_an(Hash).and be_empty
    end

    it 'has not been submitted' do
      expect(subject.submitted?).to be false
    end
  end

  describe '#add_item' do
    let (:bill)            { pos.new_bill }
    let (:basic_item)      { pos.new_item('Item', 5.5) }
    let (:tax_item)        { pos.new_item('Taxable', 40, tax:12) }
    let (:dscnt_item_free) { pos.new_item('Free', 10.5, discount:[2, 1, 0]) }
    let (:dscnt_item_off)  { pos.new_item('Off', 20, discount:[3, 2.5, 1]) }
    let (:dsc_tax_item)    { pos.new_item('Dsc_Tax', 37.3, tax:10, discount:[1, 1, 0]) }

    context 'when a basic item added' do
      context 'once' do
        before do
          bill.add_item(basic_item)
        end

        it 'will update the bills subtotal' do
          expect(bill.subtotal).to eql basic_item.price
        end

        it 'will add a clone of the item to the items list' do
          listed_item = bill.items[basic_item.name]

          expect(bill.items).to have_key(basic_item.name)
          expect(listed_item[1]).to eql 1
          expect(listed_item[0]).to have_attributes(name:     basic_item.name,
                                                    price:    basic_item.price,
                                                    discount: basic_item.discount,
                                                    price_include_vat: basic_item.price_include_vat,
                                                    tax:      basic_item.tax,
                                                    tags:     basic_item.tags)
        end

        it 'will not update tax' do
          expect(bill.tax).to eql zero
        end

        it 'will not update discount' do
          expect(bill.discount).to eql zero
        end

        it 'will not submit the bill' do
          expect(bill.submitted?).to be false
        end
      end

      context 'multiple times' do
        before do
          bill.add_item(basic_item, qty:5)
        end

        it 'will update the bills subtotal' do
          expect(bill.subtotal).to eql basic_item.price * 5
        end

        it 'will add a clone of the item to the items list' do
          listed_item = bill.items[basic_item.name]

          expect(listed_item[1]).to eql 5
          expect(listed_item[0]).to have_attributes(name:     basic_item.name,
                                                    price:    basic_item.price,
                                                    discount: basic_item.discount,
                                                    price_include_vat: basic_item.price_include_vat,
                                                    tax:      basic_item.tax,
                                                    tags:     basic_item.tags)
        end

        it 'will not update tax' do
          expect(bill.tax).to eql zero
        end

        it 'will not update discount' do
          expect(bill.discount).to eql zero
        end

        it 'will not submit the bill' do
          expect(bill.submitted?).to be false
        end
      end
    end

    context 'when a tax item added' do
      context 'once' do
        before do
          bill.add_item(tax_item)
        end

        it 'will update the bills subtotal' do
          expect(bill.subtotal).to eql Money.new(4000, pos.ccy)
        end

        it 'will update the bills tax' do
          expect(bill.tax).to eql Money.new(429, pos.ccy)
        end

        it 'will not update discount' do
          expect(bill.discount).to eql zero
        end

        it 'will not submit the bill' do
          expect(bill.submitted?).to be false
        end
      end

      context 'multiple times' do
        before do
          bill.add_item(tax_item, qty:2)
        end

        it 'will update the bills subtotal' do
          expect(bill.subtotal).to eql Money.new(8000, pos.ccy)
        end

        it 'will update the bills tax' do
          expect(bill.tax).to eql Money.new(857, pos.ccy)
        end

        it 'will not update discount' do
          expect(bill.discount).to eql zero
        end

        it 'will not submit the bill' do
          expect(bill.submitted?).to be false
        end
      end
    end

    context 'when a discounted item is added' do
      context 'and it is of type "QTY FREE"' do
        context 'and discount was triggered' do
          before do
            bill.add_item(dscnt_item_free, qty:4)
          end

          it 'will update the bills subtotal' do
            expect(bill.subtotal).to eql Money.new(3150, pos.ccy)
          end

          it 'will update the bills discount' do
            expect(bill.discount).to eql Money.new(1050, pos.ccy)
          end

          it 'will not update the bills tax' do
            expect(bill.tax).to eql zero
          end

          it 'will not submit the bill' do
            expect(bill.submitted?).to be false
          end
        end

        context 'and discount was not triggered' do
          before do
            bill.add_item(dscnt_item_free)
          end

          it 'will update the bills subtotal' do
            expect(bill.subtotal).to eql Money.new(1050, pos.ccy)
          end

          it 'will update the bills discount' do
            expect(bill.discount).to eql zero
          end

          it 'will not update the bills tax' do
            expect(bill.tax).to eql zero
          end
        end
      end

      context 'and it is of type "AMOUNT OFF"' do
        context 'and discount was triggered' do
          before do
            bill.add_item(dscnt_item_off, qty:7)
          end

          it 'will update the bills subtotal' do
            expect(bill.subtotal).to eql Money.new(13500, pos.ccy)
          end

          it 'will update the bills discount' do
            expect(bill.discount).to eql Money.new(500, pos.ccy)
          end

          it 'will not update the bills tax' do
            expect(bill.tax).to eql zero
          end

          it 'will not submit the bill' do
            expect(bill.submitted?).to be false
          end
        end

        context 'and discount was not triggered' do
          before do
            bill.add_item(dscnt_item_off, qty:2)
          end

          it 'will update the bills subtotal' do
            expect(bill.subtotal).to eql Money.new(4000, pos.ccy)
          end

          it 'will update the bills discount' do
            expect(bill.discount).to eql zero
          end

          it 'will not update the bills tax' do
            expect(bill.tax).to eql zero
          end
        end
      end
    end

    context 'when a taxed discount item added' do
      context 'and discount was triggered' do
          before do
            bill.add_item(dsc_tax_item, qty:3)
          end

          it 'will update the bills subtotal' do
            expect(bill.subtotal).to eql Money.new(7460, pos.ccy)
          end

          it 'will update the bills discount' do
            expect(bill.discount).to eql Money.new(3391, pos.ccy)
          end

          it 'will update the bills tax' do
            expect(bill.tax).to eql Money.new(678, pos.ccy)
          end

          it 'will not submit the bill' do
            expect(bill.submitted?).to be false
          end
        end

        context 'and discount was not triggered' do
          before do
            bill.add_item(dsc_tax_item)
          end

          it 'will update the bills subtotal' do
            expect(bill.subtotal).to eql Money.new(3730, pos.ccy)
          end

          it 'will update the bills tax' do
            expect(bill.tax).to eql Money.new(339, pos.ccy)
          end

          it 'will update the bills discount' do
            expect(bill.discount).to eql zero
          end
        end
    end
  end

  describe '#reset' do
    let (:bill) { pos.new_bill }
    let (:item) { pos.new_item('item', 37.3, tax:10, discount:[1, 1, 0]) }

    context 'when the bill has not been submitted do' do
      before do
        bill.add_item(item, qty:4)
      end

      it 'clears the item lis' do
        bill.reset
        expect(bill.items).to be_empty
      end

      it 'zeros out all balances' do
        bill.reset
        expect(bill.subtotal).to eql zero
        expect(bill.tax).to eql zero
        expect(bill.discount).to eql zero
      end
    end
  end
end
