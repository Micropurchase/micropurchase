require 'rails_helper'

describe MarkOtherPcardAuctionAsPaid do
  describe '#perform' do
    it 'should set paid_at to a time' do
      auction = create(:auction, :payment_needed, purchase_card: :other)
      expect(auction.paid_at).to be_nil

      MarkOtherPcardAuctionAsPaid.new(auction: auction).perform

      expect(auction.paid_at).to_not be_nil
    end

    it 'sends an email to the vendor' do
      customer = create(:customer)

      auction = create(
        :auction,
        :payment_needed,
        purchase_card: :other,
        customer: customer
      )
      mailer_double = double(deliver_later: true)
      allow(WinningBidderMailer).to receive(:auction_paid_other_pcard)
                               .with(auction: auction)
                               .and_return(mailer_double)

      MarkOtherPcardAuctionAsPaid.new(auction: auction).perform

      expect(WinningBidderMailer).to have_received(:auction_paid_other_pcard)
                                .with(auction: auction)
      expect(mailer_double).to have_received(:deliver_later)
    end
  end
end
