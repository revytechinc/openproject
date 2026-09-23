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

RSpec.describe WorkPackages::LiveUpdateBroadcaster do
  let(:work_package) do
    build_stubbed(:work_package, lock_version: 4, updated_at: Time.zone.local(2026, 9, 23, 12, 0, 0))
  end

  before do
    ActionCable.server.pubsub.clear_messages(WorkPackageChannel.project_stream(work_package.project_id))
    ActionCable.server.pubsub.clear_messages(WorkPackageChannel.work_package_stream(work_package.id))
  end

  def journal_for(notes:, initial:, details:)
    journal = instance_double(
      Journal,
      journable_type: "WorkPackage",
      journable: work_package,
      notes:,
      details:
    )
    allow(journal).to receive(:initial?).and_return(initial)
    journal
  end

  def payloads(stream)
    ActionCable.server.pubsub.broadcasts(stream).map { |payload| JSON.parse(payload, symbolize_names: true) }
  end

  it "broadcasts status and assignee changes without the comment text" do
    journal = journal_for(
      notes: "secret comment",
      initial: false,
      details: { "status_id" => [1, 2], "assigned_to_id" => [3, 4], "subject" => %w[old new] }
    )

    described_class.call(journal)

    expected = {
      work_package_id: work_package.id,
      project_id: work_package.project_id,
      changed: %w[comment status assignee],
      lock_version: 4,
      updated_at: work_package.updated_at.iso8601
    }

    expect(payloads(WorkPackageChannel.project_stream(work_package.project_id))).to eq([expected])
    expect(payloads(WorkPackageChannel.work_package_stream(work_package.id))).to eq([expected])
    expect(expected).not_to have_key(:notes)
  end

  it "does not broadcast the initial status and assignee snapshot" do
    journal = journal_for(notes: "", initial: true, details: { "status_id" => [nil, 1], "assigned_to_id" => [nil, 2] })

    described_class.call(journal)

    expect(payloads(WorkPackageChannel.work_package_stream(work_package.id))).to be_empty
  end

  it "broadcasts a comment on the initial journal" do
    journal = journal_for(notes: "created with a comment", initial: true, details: { "status_id" => [nil, 1] })

    described_class.call(journal)

    payload = payloads(WorkPackageChannel.work_package_stream(work_package.id)).first
    expect(payload[:changed]).to eq(["comment"])
    expect(payload).not_to have_key(:notes)
  end

  it "ignores journals that are not work packages" do
    journal = instance_double(Journal, journable_type: "WikiPage", journable: work_package, notes: "note")
    allow(journal).to receive(:initial?).and_return(false)

    described_class.call(journal)

    expect(payloads(WorkPackageChannel.work_package_stream(work_package.id))).to be_empty
  end
end
