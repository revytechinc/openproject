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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

# Journal#bcf_comment is defined by the BIM module only. Builds shipping without
# BIM must not eager load it, or the tool fails with
# ActiveRecord::AssociationNotFoundError.
RSpec.describe McpTools::ListWorkPackageComments, "eager loading of bcf_comment", # rubocop:disable RSpec/SpecFilePathFormat
               with_ee: %i[mcp_server] do
  subject(:mcp_request) do
    header "Authorization", "Bearer #{access_token.plaintext_token}"
    header "Content-Type", "application/json"
    post "/mcp", request_body.to_json
  end

  let(:access_token) do
    create(:oauth_access_token, scopes: "mcp", resource_owner: user, application: create(:oauth_application, owner: nil))
  end
  let(:user) { create(:user) }
  let(:project) { create(:project) }
  let!(:work_package) { create(:work_package, project:) }

  let(:request_body) do
    {
      jsonrpc: "2.0",
      id: "Test-Request",
      method: "tools/call",
      params: {
        name: "list_work_package_comments",
        arguments: { work_package_id: work_package.id }
      }
    }
  end
  let(:parsed_results) { JSON.parse(last_response.body).fetch("result") }
  let(:included_associations) { [] }

  before do
    create(:mcp_configuration, identifier: "mcp_server").save!
    create(:mcp_configuration, identifier: described_class.qualified_name).save!
    create(:member, project:, user:, roles: [create(:project_role, permissions: %i[view_work_packages])])
    work_package.journals.last.update!(notes: "A comment")

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

      mcp_request
    end

    it "lists the comments without eager loading bcf_comment" do
      expect(parsed_results.dig("structuredContent", "items").size).to eq(1)
      expect(included_associations).to include(:data)
      expect(included_associations).not_to include(:bcf_comment)
    end
  end

  context "when the bcf_comment association is defined (BIM module loaded)" do
    before do
      skip "BIM module not loaded" unless Journal.reflect_on_association(:bcf_comment)

      mcp_request
    end

    it "eager loads bcf_comment as before" do
      expect(parsed_results.dig("structuredContent", "items").size).to eq(1)
      expect(included_associations).to include(:bcf_comment)
    end
  end
end
