//-- copyright
// OpenProject is an open source project management software.
// Copyright (C) the OpenProject GmbH
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License version 3.
//
// OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
// Copyright (C) 2006-2013 Jean-Philippe Lang
// Copyright (C) 2010-2013 the ChiliProject Team
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
//
// See COPYRIGHT and LICENSE files for more details.
//++

import { Controller } from '@hotwired/stimulus';
import type { ApiV3Service } from 'core-app/core/apiv3/api-v3.service';
import {
  openWorkPackageCable,
  type WorkPackageCable,
  type WorkPackageLiveDelta,
} from 'core-stimulus/helpers/action-cable-client';
import { useAngularServices, type PickedServices, type ServiceKey } from 'core-stimulus/mixins/use-angular-services';

export default class LiveUpdatesController extends Controller {
  static services:ServiceKey[] = ['apiV3Service'];

  static values = {
    projectId: Number,
    workPackageId: Number,
    visibleProjects: Boolean,
  };

  declare projectIdValue:number;
  declare readonly hasProjectIdValue:boolean;
  declare workPackageIdValue:number;
  declare readonly hasWorkPackageIdValue:boolean;
  declare visibleProjectsValue:boolean;

  declare apiV3Service:ApiV3Service;
  declare services:Promise<PickedServices<'apiV3Service'>>;

  private cable?:WorkPackageCable;

  initialize():void {
    super.initialize();
    useAngularServices(this);
  }

  connect():void {
    const params = this.subscriptionParams();
    if (!params) return;

    this.cable = openWorkPackageCable({
      params,
      onMessage: (delta) => {
        void this.applyDelta(delta);
      },
    });
  }

  disconnect():void {
    this.cable?.close();
    this.cable = undefined;
  }

  private subscriptionParams():Record<string, number | boolean> | null {
    if (this.hasWorkPackageIdValue && this.workPackageIdValue > 0) {
      return { work_package_id: this.workPackageIdValue };
    }

    if (this.hasProjectIdValue && this.projectIdValue > 0) {
      return { project_id: this.projectIdValue };
    }

    if (this.visibleProjectsValue) {
      return { visible_projects: true };
    }

    return null;
  }

  private async applyDelta(delta:WorkPackageLiveDelta):Promise<void> {
    document.dispatchEvent(new CustomEvent('work-package-live-update', {
      detail: {
        workPackageId: delta.work_package_id,
        changed: delta.changed,
      },
    }));

    if (this.inlineEditBlocksRefresh(String(delta.work_package_id))) return;

    try {
      const { apiV3Service } = await this.services;
      const id = String(delta.work_package_id);
      const state = apiV3Service.work_packages.cache.state(id);
      if (!state.hasValue()) return;

      const current = state.value as { lockVersion?:number } | undefined;
      if (
        current?.lockVersion != null
        && delta.lock_version != null
        && current.lockVersion >= delta.lock_version
      ) {
        return;
      }

      await apiV3Service.work_packages.id(id).refresh();
    } catch (error) {
      console.error('Work package live update refresh failed:', error);
    }
  }

  private inlineEditBlocksRefresh(workPackageId:string):boolean {
    const active = document.querySelector('.inline-edit--active-field');
    if (!active) return false;

    const rowId = active.closest<HTMLElement>('[data-work-package-id]')?.dataset.workPackageId;
    if (rowId) return rowId === workPackageId;

    const openId = document.getElementById('work-packages--activities-tab--index')
      ?.getAttribute('data-work-packages--activities-tab--index-work-package-id-value');
    if (openId) return openId === workPackageId;

    return true;
  }
}
