#
require 'spec_helper'
require_relative '../pos'

describe POS do
  let(:pos) { POS.new }
  let(:default_currency) { "gbp" }
  
  context 'with no parameters' do
    it 'has default values' do
      expect(pos.ccy).to eql default_currency
      expect(pos.ref).to eql 0
      expect(pos.bill_list).to eql({})
      expect(pos.system_total).to eql Money.new(0, default_currency)
    end
  end
  
  context 'with parameters' do
    let (:currency) { "usd"}
    let (:new_pos) { POS.new(currency, enforce_locales:true, ref_start:70) }
    
    it 'holds user values' do
      expect(new_pos.ccy).to eql currency
      expect(new_pos.ref).to eql 69
      expect(new_pos.bill_list).to eql({})
      expect(new_pos.system_total).to eql Money.new(0, currency)
    end
  end
  
  describe '#new_bill' do
    let(:bill) { pos.new_bill }
    
    it 'will create a bill object' do
      expect(bill).to be_an_instance_of Bill
      expect(bill.bill_ref).to eql pos.ref
    end
  end
  
  describe '#new_item' do
    it 'will create an item object' do
      item = pos.new_item("item", 0)
      expect(item).to be_an_instance_of Item
    end
  end
end

describe Item do
  let(:pos) { POS.new }
  
  context 'with no keywords' do
    let (:item) { pos.new_item('test', 0) }
    
    it 'has default values' do
      expect(item.name).to eql :test
      expect(item.price).to eql Money.new(0, pos.ccy)
      expect(item.tax).to eql 0.0
      expect(item.discount).to be false
      expect(item.tags).to eql([])
      expect(item.price_include_vat).to be true
    end
  end
  
  context 'with user defined keywords' do
    let (:item) do
      pos.new_item('test', 5.50,
        discount:[1, 1, 0], 
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
    
    it 'turns new tags into symbols' do
      item.tags<<"Hello_World"
      expect(item.tags[-1]).to eql :hello_world
    end
    
    it 'turns new price into a money object' do
      item.price = 
    end
  end
end

