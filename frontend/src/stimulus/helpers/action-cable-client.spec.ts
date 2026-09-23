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

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  openWorkPackageCable,
  workPackageCableUrl,
  type CableSocket,
  type WorkPackageLiveDelta,
} from './action-cable-client';

class FakeSocket implements CableSocket {
  static instances:FakeSocket[] = [];

  sent:string[] = [];

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
    this.onclose?.(new Event('close'));
  }

  open() {
    this.onopen?.(new Event('open'));
  }

  receive(payload:unknown) {
    this.onmessage?.({ data: JSON.stringify(payload) });
  }
}

describe('work package action cable client', () => {
  afterEach(() => {
    vi.useRealTimers();
    FakeSocket.instances = [];
    delete document.body.dataset.relativeUrlRoot;
  });

  it('builds a same-origin cable url from the relative url root', () => {
    document.body.dataset.relativeUrlRoot = '/op/';

    const scheme = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    expect(workPackageCableUrl()).toBe(`${scheme}//${window.location.host}/op/cable`);
  });

  it('subscribes and forwards work package deltas', () => {
    const messages:WorkPackageLiveDelta[] = [];
    openWorkPackageCable({
      params: { project_id: 4 },
      onMessage: (delta) => messages.push(delta),
      url: 'ws://example.test/cable',
      socketFactory: (url) => new FakeSocket(url),
      reconnect: false,
    });

    const socket = FakeSocket.instances[0];
    socket.open();

    expect(socket.url).toBe('ws://example.test/cable');
    expect(JSON.parse(socket.sent[0])).toEqual({
      command: 'subscribe',
      identifier: JSON.stringify({ channel: 'WorkPackageChannel', project_id: 4 }),
    });

    socket.receive({ type: 'confirm_subscription' });
    socket.receive({ type: 'ping', message: 1 });
    socket.receive({
      message: {
        work_package_id: 9,
        project_id: 4,
        changed: ['status'],
        lock_version: 2,
        updated_at: '2026-09-23T12:00:00Z',
      },
    });

    expect(messages).toEqual([
      {
        work_package_id: 9,
        project_id: 4,
        changed: ['status'],
        lock_version: 2,
        updated_at: '2026-09-23T12:00:00Z',
      },
    ]);
  });

  it('does not reconnect after the server rejects the subscription', () => {
    vi.useFakeTimers();
    openWorkPackageCable({
      params: { project_id: 4 },
      onMessage: () => undefined,
      url: 'ws://example.test/cable',
      socketFactory: (url) => new FakeSocket(url),
    });

    const socket = FakeSocket.instances[0];
    socket.open();
    socket.receive({ type: 'reject_subscription' });
    vi.advanceTimersByTime(20_000);

    expect(FakeSocket.instances).toHaveLength(1);
  });

  it('reconnects after the socket drops', () => {
    vi.useFakeTimers();
    const cable = openWorkPackageCable({
      params: { work_package_id: 9 },
      onMessage: () => undefined,
      url: 'ws://example.test/cable',
      socketFactory: (url) => new FakeSocket(url),
    });

    FakeSocket.instances[0].open();
    FakeSocket.instances[0].close();
    vi.advanceTimersByTime(1000);

    expect(FakeSocket.instances).toHaveLength(2);
    FakeSocket.instances[1].open();
    expect(JSON.parse(FakeSocket.instances[1].sent[0]).command).toBe('subscribe');

    cable.close();
    FakeSocket.instances[1].close();
    vi.advanceTimersByTime(20_000);
    expect(FakeSocket.instances).toHaveLength(2);
  });
});
