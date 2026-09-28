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

RSpec.describe Journal, ".optional_module_includes" do # rubocop:disable RSpec/SpecFilePathFormat
  context "when the bcf_comment association is not defined (BIM module not loaded)" do
    before do
      allow(described_class).to receive(:reflect_on_association).and_call_original
      allow(described_class).to receive(:reflect_on_association).with(:bcf_comment).and_return(nil)
    end

    it "returns no includes" do
      expect(described_class.optional_module_includes).to eq([])
    end
  end

  context "when the bcf_comment association is defined (BIM module loaded)" do
    before do
      skip "BIM module not loaded" unless described_class.reflect_on_association(:bcf_comment)
    end

    it "returns bcf_comment" do
      expect(described_class.optional_module_includes).to eq(%i[bcf_comment])
    end
  end

  it "is evaluated on every call rather than memoized" do
    reflection = instance_double(ActiveRecord::Reflection::HasOneReflection)
    allow(described_class).to receive(:reflect_on_association).and_call_original
    allow(described_class).to receive(:reflect_on_association).with(:bcf_comment).and_return(nil, reflection)

    expect(described_class.optional_module_includes).to eq([])
    expect(described_class.optional_module_includes).to eq(%i[bcf_comment])
  end
end
