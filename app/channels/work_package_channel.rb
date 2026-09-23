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

class WorkPackageChannel < ApplicationCable::Channel
  def subscribed
    if params[:work_package_id].present?
      subscribe_work_package
    elsif params[:project_id].present?
      subscribe_project
    elsif ActiveModel::Type::Boolean.new.cast(params[:visible_projects])
      subscribe_visible_projects
    else
      reject
    end
  end

  def self.broadcast_delta(work_package, changed)
    payload = {
      work_package_id: work_package.id,
      project_id: work_package.project_id,
      changed:,
      lock_version: work_package.lock_version,
      updated_at: work_package.updated_at&.iso8601
    }

    ActionCable.server.broadcast(project_stream(work_package.project_id), payload)
    ActionCable.server.broadcast(work_package_stream(work_package.id), payload)
  end

  def self.project_stream(project_id)
    "work_packages:project:#{project_id}"
  end

  def self.work_package_stream(work_package_id)
    "work_packages:#{work_package_id}"
  end

  private

  def subscribe_work_package
    work_package = WorkPackage.visible(current_user).find_by(id: params[:work_package_id])
    if work_package
      stream_from self.class.work_package_stream(work_package.id)
    else
      reject
    end
  end

  def subscribe_project
    project = Project.allowed_to(current_user, :view_work_packages).find_by(id: params[:project_id])
    if project
      stream_from self.class.project_stream(project.id)
    else
      reject
    end
  end

  def subscribe_visible_projects
    project_ids = Project.allowed_to(current_user, :view_work_packages).pluck(:id)
    if project_ids.empty?
      reject
    else
      project_ids.each { |project_id| stream_from(self.class.project_stream(project_id)) }
    end
  end
end
