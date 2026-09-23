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

RSpec.describe WorkPackageChannel, type: :channel do
  shared_let(:project) { create(:project) }
  shared_let(:other_project) { create(:project) }
  shared_let(:work_package) { create(:work_package, project:) }
  shared_let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }

  before { stub_connection current_user: user }

  it "rejects a subscription without a target" do
    subscribe

    expect(subscription).to be_rejected
  end

  it "streams a visible work package" do
    subscribe(work_package_id: work_package.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from(described_class.work_package_stream(work_package.id))
  end

  it "rejects a work package the user cannot view" do
    hidden = create(:work_package, project: other_project)

    subscribe(work_package_id: hidden.id)

    expect(subscription).to be_rejected
  end

  it "streams a project the user can view work packages in" do
    subscribe(project_id: project.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from(described_class.project_stream(project.id))
  end

  it "rejects a project the user cannot view" do
    subscribe(project_id: other_project.id)

    expect(subscription).to be_rejected
  end

  it "streams every project the user can view" do
    subscribe(visible_projects: true)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from(described_class.project_stream(project.id))
    expect(subscription).not_to have_stream_from(described_class.project_stream(other_project.id))
  end

  it "rejects a visible-project subscription when the user can view none" do
    stub_connection current_user: create(:user)

    subscribe(visible_projects: true)

    expect(subscription).to be_rejected
  end
end
