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

export interface WorkPackageLiveDelta {
  work_package_id:number;
  project_id:number;
  changed:string[];
  lock_version:number | null;
  updated_at:string | null;
}

export interface CableSocket {
  send(data:string):void;
  close():void;
  onopen:((event:Event) => void) | null;
  onmessage:((event:{ data:string }) => void) | null;
  onclose:((event:Event) => void) | null;
}

export interface OpenWorkPackageCableOptions {
  params:Record<string, string | number | boolean>;
  onMessage:(delta:WorkPackageLiveDelta) => void;
  url?:string;
  socketFactory?:(url:string) => CableSocket;
  reconnect?:boolean;
}

export interface WorkPackageCable {
  close():void;
}

const RECONNECT_MAX_MS = 15_000;

export function workPackageCableUrl():string {
  const root = document.body?.dataset.relativeUrlRoot ?? '/';
  const prefix = root.endsWith('/') ? root.slice(0, -1) : root;
  const scheme = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${scheme}//${window.location.host}${prefix}/cable`;
}

export function openWorkPackageCable(options:OpenWorkPackageCableOptions):WorkPackageCable {
  const identifier = JSON.stringify({ channel: 'WorkPackageChannel', ...options.params });
  const reconnect = options.reconnect !== false;
  let stopped = false;
  let rejected = false;
  let attempt = 0;
  let timer = 0;
  let socket:CableSocket | null = null;

  const handleMessage = (raw:string) => {
    let data:{ type?:string, message?:WorkPackageLiveDelta };
    try {
      data = JSON.parse(raw) as { type?:string, message?:WorkPackageLiveDelta };
    } catch {
      return;
    }

    if (data.type === 'reject_subscription') {
      rejected = true;
      socket?.close();
      return;
    }

    if (data.type === 'ping' || data.type === 'welcome' || data.type === 'confirm_subscription') {
      return;
    }

    if (data.message && typeof data.message.work_package_id === 'number') {
      options.onMessage(data.message);
    }
  };

  const connect = () => {
    if (stopped || rejected) return;

    const url = options.url ?? workPackageCableUrl();
    const factory = options.socketFactory ?? ((nextUrl:string) => new WebSocket(nextUrl));
    socket = factory(url);
    socket.onopen = () => {
      attempt = 0;
      socket?.send(JSON.stringify({ command: 'subscribe', identifier }));
    };
    socket.onmessage = (event) => {
      handleMessage(event.data);
    };
    socket.onclose = () => {
      socket = null;
      if (stopped || rejected || !reconnect) return;

      attempt += 1;
      const delay = Math.min(RECONNECT_MAX_MS, 1000 * (2 ** (attempt - 1)));
      timer = window.setTimeout(connect, delay);
    };
  };

  connect();

  return {
    close() {
      stopped = true;
      window.clearTimeout(timer);
      socket?.close();
      socket = null;
    },
  };
}
