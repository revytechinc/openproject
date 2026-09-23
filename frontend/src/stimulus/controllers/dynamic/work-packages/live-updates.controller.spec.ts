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

import { vi } from 'vitest';
import { setupStimulusTest, type StimulusTestContext } from 'core-stimulus/test-helpers';
import type { WorkPackageLiveDelta } from 'core-stimulus/helpers/action-cable-client';
import type LiveUpdatesControllerType from './live-updates.controller';

class FakeSocket {
  static instances:FakeSocket[] = [];

  sent:string[] = [];

  closed = false;

  onopen:((event:Event) => void) | null = null;

  onmessage:((event:{ data:string }) => void) | null = null;

  onclose:((event:Event) => void) | null = null;

  constructor(public url:string) {
    FakeSocket.instances.push(this);
  }

  send(data:string) {
    this.sent.push(data);
  }

  close() {
    this.closed = true;
    this.onclose?.(new Event('close'));
  }

  open() {
    this.onopen?.(new Event('open'));
  }

  receive(payload:unknown) {
    this.onmessage?.({ data: JSON.stringify(payload) });
  }
}

describe('Work package live updates controller', () => {
  let ctx:StimulusTestContext;
  let LiveUpdatesController:typeof LiveUpdatesControllerType;
  let resolveContext:(context:unknown) => void;
  let originalOpenProject:typeof window.OpenProject;
  let refresh:ReturnType<typeof vi.fn>;
  let hasValue:ReturnType<typeof vi.fn>;
  let stateValue:{ lockVersion:number };
  let received:number[];
  let onLiveUpdate:(event:Event) => void;

  const delta = (overrides:Partial<WorkPackageLiveDelta> = {}):WorkPackageLiveDelta => ({
    work_package_id: 7,
    project_id: 3,
    changed: ['status'],
    lock_version: 2,
    updated_at: '2026-09-23T12:00:00Z',
    ...overrides,
  });

  beforeAll(async () => {
    ({ default: LiveUpdatesController } = await import('./live-updates.controller'));
  });

  beforeEach(async () => {
    FakeSocket.instances = [];
    vi.stubGlobal('WebSocket', FakeSocket);
    refresh = vi.fn().mockResolvedValue(undefined);
    hasValue = vi.fn().mockReturnValue(true);
    stateValue = { lockVersion: 1 };
    received = [];
    onLiveUpdate = (event:Event) => {
      received.push((event as CustomEvent<{ workPackageId:number }>).detail.workPackageId);
    };
    document.addEventListener('work-package-live-update', onLiveUpdate);

    originalOpenProject = window.OpenProject;
    const contextPromise = new Promise((resolve) => { resolveContext = resolve; });
    window.OpenProject = {
      getPluginContext: () => contextPromise,
    } as unknown as typeof window.OpenProject;

    ctx = await setupStimulusTest({
      controllers: { 'work-packages--live-updates': LiveUpdatesController },
    });
  });

  afterEach(() => {
    document.removeEventListener('work-package-live-update', onLiveUpdate);
    ctx.dispose();
    window.OpenProject = originalOpenProject;
    document.body.innerHTML = '';
    vi.unstubAllGlobals();
  });

  async function mount(html:string) {
    await ctx.mount(html);
    resolveContext({
      services: {
        apiV3Service: {
          work_packages: {
            cache: { state: () => ({ hasValue, value: stateValue }) },
            id: vi.fn(() => ({ refresh })),
          },
        },
      },
    });
    await ctx.nextFrame();
  }

  function socket():FakeSocket {
    const current = FakeSocket.instances[0];
    expect(current).toBeTruthy();
    return current;
  }

  function subscription() {
    const current = socket();
    current.open();
    const frame = JSON.parse(current.sent[0]) as { identifier:string };
    return JSON.parse(frame.identifier) as Record<string, unknown>;
  }

  async function deliver(payload:WorkPackageLiveDelta) {
    socket().receive({ message: payload });
    await ctx.nextFrame();
  }

  it('subscribes a project list and refreshes a cached work package', async () => {
    await mount('<div data-controller="work-packages--live-updates" data-work-packages--live-updates-project-id-value="4"></div>');

    expect(subscription()).toEqual({ channel: 'WorkPackageChannel', project_id: 4 });
    await deliver(delta());

    expect(received).toEqual([7]);
    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it('subscribes the open work package on the detail page', async () => {
    await mount('<div data-controller="work-packages--live-updates" data-work-packages--live-updates-work-package-id-value="7"></div>');

    expect(subscription()).toEqual({ channel: 'WorkPackageChannel', work_package_id: 7 });
  });

  it('subscribes visible projects on the global list', async () => {
    await mount('<div data-controller="work-packages--live-updates" data-work-packages--live-updates-visible-projects-value="true"></div>');

    expect(subscription()).toEqual({ channel: 'WorkPackageChannel', visible_projects: true });
  });

  it('skips the refresh when the cached lock version is already current', async () => {
    stateValue = { lockVersion: 2 };
    await mount('<div data-controller="work-packages--live-updates" data-work-packages--live-updates-project-id-value="4"></div>');

    await deliver(delta());

    expect(received).toEqual([7]);
    expect(refresh).not.toHaveBeenCalled();
  });

  it('skips the refresh while that work package row is being edited', async () => {
    await mount(`
      <div data-controller="work-packages--live-updates" data-work-packages--live-updates-project-id-value="4"></div>
      <table><tr data-work-package-id="7"><td class="inline-edit--active-field"></td></tr></table>
    `);

    await deliver(delta());
    expect(refresh).not.toHaveBeenCalled();

    await deliver(delta({ work_package_id: 8, lock_version: 3 }));
    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it('closes the socket on disconnect', async () => {
    await mount('<div data-controller="work-packages--live-updates" data-work-packages--live-updates-project-id-value="4"></div>');
    const current = socket();

    ctx.container.querySelector('[data-controller="work-packages--live-updates"]')?.remove();
    await ctx.nextFrame();

    expect(current.closed).toBe(true);
    expect(FakeSocket.instances).toHaveLength(1);
  });
});
