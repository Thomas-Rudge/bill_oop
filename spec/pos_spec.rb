#
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
  subject { pos.new_bill }

  context 'instantiated' do
    let (:starting_balance) { Money.new(0, pos.ccy) }
    it 'has nil balances' do
      expect(subject.subtotal).to eql starting_balance
      expect(subject.tax).to eql      starting_balance
      expect(subject.discount).to eql starting_balance
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

    context 'when a single item added' do
      context 'add a basic item once' do
        it 'will update the bills subtotal' do
          bill.add_item(basic_item)
          expect(bill.subtotal).to eql basic_item.price
        end

        it 'will add a clone of the item to the items list' do
          bill.add_item(basic_item)
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
      end
    end
  end
end
