require 'rails_helper'

describe AcceptAuction do
  describe '#perform' do
    context 'auction belongs to a customer' do
      context 'customer has an email' do
        it 'sends an email to the customer' do
          customer = create(:customer, email: 'test@example.com')
          auction = create(:auction, customer: customer)
          mailer_double = double(deliver_later: true)
          allow(AuctionMailer).to receive(:auction_accepted_customer_notification)
            .with(auction: auction)
            .and_return(mailer_double)

          AcceptAuction.new(auction: auction, payment_url: 'example.com').perform

          expect(AuctionMailer).to have_received(:auction_accepted_customer_notification)
            .with(auction: auction)
          expect(mailer_double).to have_received(:deliver_later)
        end
      end

      context 'customer does not have an email' do
        it 'does not send an email to the customer' do
          customer = create(:customer, email: nil)
          auction = create(:auction, :with_bids, customer: customer)
          allow(AuctionMailer).to receive(:auction_accepted_customer_notification)

          AcceptAuction.new(auction: auction, payment_url: 'example.com').perform

          expect(AuctionMailer).not_to have_received(:auction_accepted_customer_notification)
        end
      end
    end

    context 'auction does not belong to a customer' do
      it 'does not send an email' do
        auction = create(:auction, :with_bids, customer: nil)
        allow(AuctionMailer).to receive(:auction_accepted_customer_notification)

        AcceptAuction.new(auction: auction, payment_url: 'example.com').perform

        expect(AuctionMailer).not_to have_received(:auction_accepted_customer_notification)
      end
    end

    context 'winning bidder does not have credit card information' do
      it 'sends an email to the winner' do
        auction = create(:auction, :with_bids)
        mailer_double = double(deliver_later: true)
        allow(WinningBidderMailer).to receive(:auction_accepted_missing_payment_method)
          .with(auction: auction)
          .and_return(mailer_double)

        AcceptAuction.new(auction: auction, payment_url: '').perform

        expect(WinningBidderMailer).to have_received(:auction_accepted_missing_payment_method)
          .with(auction: auction)
        expect(mailer_double).to have_received(:deliver_later)
        expect(auction.delivery_status).to eq 'accepted_pending_payment_url'
      end
    end

    context 'winning bidder has credit card information' do
      it 'sends an email to the winner' do
        auction = create(:auction, :with_bids)
        mailer_double = double(deliver_later: true)
        allow(WinningBidderMailer).to receive(:auction_accepted)
          .with(auction: auction)
          .and_return(mailer_double)

        AcceptAuction.new(auction: auction, payment_url: 'example.com').perform

        expect(WinningBidderMailer).to have_received(:auction_accepted)
          .with(auction: auction)
        expect(mailer_double).to have_received(:deliver_later)
      end

      context 'auction is for 18F purchase card' do
        it 'enqueues the UpdateC2ProposalJob' do
          auction = create(:auction, :with_bids)
          allow(UpdateC2ProposalJob).to receive(:perform_later)

          AcceptAuction.new(auction: auction, payment_url: 'example.com').perform

          expect(UpdateC2ProposalJob).to have_received(:perform_later).with(auction.id, 'C2UpdateAttributes')
        end
      end

      context 'auction is for other purchase card' do
        it 'does not enqueue the UpdateC2ProposalJob' do
          auction = create(:auction, :with_bids, purchase_card: :other)
          allow(UpdateC2ProposalJob).to receive(:perform_later)

          AcceptAuction.new(auction: auction, payment_url: 'test.com').perform

          expect(UpdateC2ProposalJob).not_to have_received(:perform_later).with(auction.id)
        end
      end

      it 'sets accepted_at' do
        auction = create(:auction, :with_bids)
        time = Time.parse('10:00:00 UTC')

        Timecop.freeze(time) do
          auction = create(:auction, :with_bids, accepted_at: nil)

          AcceptAuction.new(
            auction: auction,
            payment_url: 'test.com'
          ).perform

          expect(auction.accepted_at).to eq time
          expect(auction).to be_accepted
        end
      end
    end

    context 'auction is between micropurchase and SAT threshold' do
      context 'winning vendor is a small business' do
        it 'calls the AcceptAuctionJob' do
          auction = create(
            :auction,
            :between_micropurchase_and_sat_threshold,
            :winning_vendor_is_small_business,
            :delivery_due_at_expired
          )

          AcceptAuction.new(
            auction: auction,
            payment_url: "https://some-website.com/pay"
          ).perform

          expect(auction).to be_accepted
        end
      end

      context 'winning vendor is not a small business' do
        it 'returns false' do
          auction = create(
            :auction,
            :between_micropurchase_and_sat_threshold,
            :winning_vendor_is_non_small_business,
            :delivery_due_at_expired
          )

          accept_auction = AcceptAuction.new(
            auction: auction,
            payment_url: "https://some-website.com/pay"
          )

          expect(accept_auction.perform).to eq false
          expect(auction).not_to be_accepted
          expect(auction.errors.full_messages).to include(
            I18n.t('errors.update_auction.vendor_ineligible')
          )
        end
      end
    end
  end
end
