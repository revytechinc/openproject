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
require "rack/test"

# Journal#bcf_comment is defined by the BIM module only. Builds shipping without
# BIM must not eager load it, or the activities endpoint fails with
# ActiveRecord::AssociationNotFoundError.
RSpec.describe API::V3::Activities::ActivitiesByWorkPackageAPI, "eager loading of bcf_comment" do # rubocop:disable RSpec/SpecFilePathFormat
  include API::V3::Utilities::PathHelper

  shared_let(:admin) { create(:admin) }
  shared_let(:work_package) { create(:work_package, author: admin) }

  let(:included_associations) { [] }

  before do
    allow(User).to receive(:current).and_return(admin)

    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(ActiveRecord::Relation).to receive(:includes).and_wrap_original do |original, *args|
      included_associations.concat(args.flatten)
      original.call(*args)
    end
    # rubocop:enable RSpec/AnyInstance
  end

  context "when the bcf_comment association is not defined (BIM module not loaded)" do
    before do
      allow(Journal).to receive(:reflect_on_association).and_call_original
      allow(Journal).to receive(:reflect_on_association).with(:bcf_comment).and_return(nil)

      get api_v3_paths.work_package_activities(work_package.id)
    end

    it "succeeds without eager loading bcf_comment" do
      expect(last_response).to have_http_status :ok
      expect(JSON.parse(last_response.body).dig("_embedded", "elements")).not_to be_empty
      expect(included_associations).to include(:data)
      expect(included_associations).not_to include(:bcf_comment)
    end
  end

  context "when the bcf_comment association is defined (BIM module loaded)" do
    before do
      skip "BIM module not loaded" unless Journal.reflect_on_association(:bcf_comment)

      get api_v3_paths.work_package_activities(work_package.id)
    end

    it "eager loads bcf_comment as before" do
      expect(last_response).to have_http_status :ok
      expect(included_associations).to include(:bcf_comment)
    end
  end
end
