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

RSpec.describe Journal::WorkPackageLiveUpdates do
  let(:work_package) { build_stubbed(:work_package) }

  it "runs after a journal is created" do
    filters = Journal._commit_callbacks.map(&:filter)

    expect(filters).to include(:broadcast_work_package_live_update)
  end

  it "broadcasts a work package journal" do
    journal = Journal.new(journable_type: "WorkPackage", journable: work_package, notes: "hello", version: 2)
    allow(journal).to receive(:details).and_return("status_id" => [1, 2])
    allow(WorkPackages::LiveUpdateBroadcaster).to receive(:call)

    journal.send(:broadcast_work_package_live_update)

    expect(WorkPackages::LiveUpdateBroadcaster).to have_received(:call).with(journal)
  end

  it "skips journals for other models" do
    journal = Journal.new(journable_type: "WikiPage", notes: "hello", version: 2)
    allow(WorkPackages::LiveUpdateBroadcaster).to receive(:call)

    journal.send(:broadcast_work_package_live_update)

    expect(WorkPackages::LiveUpdateBroadcaster).not_to have_received(:call)
  end

  it "logs and swallows broadcast failures" do
    journal = Journal.new(journable_type: "WorkPackage", journable: work_package, notes: "hello", version: 2)
    allow(WorkPackages::LiveUpdateBroadcaster).to receive(:call).and_raise(RuntimeError, "redis down")
    allow(OpenProject.logger).to receive(:error)

    expect { journal.send(:broadcast_work_package_live_update) }.not_to raise_error
    expect(OpenProject.logger).to have_received(:error).with(/redis down/)
  end
end
