# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

RSpec.describe Journals::CreateService do
  describe "work package live updates" do
    let(:journable) { instance_double(WorkPackage, id: 7) }
    let(:user) { instance_double(User, id: 3) }
    let(:service) { described_class.new(journable, user) }
    let(:journal) { instance_double(Journal) }
    let(:db_transaction) { instance_double(ActiveRecord::Transaction) }
    let(:commit_callbacks) { [] }

    before do
      allow(described_class::Association).to receive(:for).and_return([])
      allow(db_transaction).to receive(:after_commit) { |&block| commit_callbacks << block }
      allow(Journal).to receive(:transaction) { |&block| block.call(db_transaction) }
      allow(service).to receive(:reload_journals)
      allow(WorkPackages::LiveUpdateBroadcaster).to receive(:call)
    end

    it "broadcasts a written journal only after the transaction commits" do
      allow(service).to receive(:create_journal).and_return(journal)

      result = service.call

      expect(result).to be_success
      expect(result.result).to eq(journal)
      expect(WorkPackages::LiveUpdateBroadcaster).not_to have_received(:call)

      commit_callbacks.each(&:call)

      expect(WorkPackages::LiveUpdateBroadcaster).to have_received(:call).with(journal).once
    end

    it "does not schedule a broadcast when no journal is written" do
      allow(service).to receive(:create_journal).and_return(nil)

      result = service.call

      expect(result).to be_success
      expect(result.result).to be_nil
      expect(db_transaction).not_to have_received(:after_commit)
      expect(WorkPackages::LiveUpdateBroadcaster).not_to have_received(:call)
    end

    it "does not schedule a broadcast when the insert fails" do
      allow(service).to receive(:create_journal).and_raise(ActiveRecord::StatementInvalid, "insert failed")

      expect { service.call }.to raise_error(ActiveRecord::StatementInvalid)
      expect(db_transaction).not_to have_received(:after_commit)
      expect(WorkPackages::LiveUpdateBroadcaster).not_to have_received(:call)
    end

    it "logs a broadcast failure and keeps the created journal" do
      allow(service).to receive(:create_journal).and_return(journal)
      allow(WorkPackages::LiveUpdateBroadcaster).to receive(:call).and_raise(RuntimeError, "redis down")
      allow(OpenProject.logger).to receive(:error)

      result = service.call

      expect { commit_callbacks.each(&:call) }.not_to raise_error
      expect(result).to be_success
      expect(result.result).to eq(journal)
      expect(OpenProject.logger).to have_received(:error).with(/redis down/)
    end
  end
end
