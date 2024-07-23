#!/usr/bin/env python3

import argparse
import inotify.adapters
import logging
import logging.handlers
import os
import requests
import sqlite3
import stat
import sys
import threading
import time

logger = None
sys_db_path = os.path.expanduser('~/.SynologyDrive/data/db/sys.sqlite')
# The file should be modified at least this often (seconds) or something is
# wrong and we shouldn't update the canary.
sys_db_max_idle = 120


class TaskWatcher(object):
    def __init__(self, path):
        if path.endswith(os.path.sep):
            path = os.path.dirname(path)
        logger.info('Starting watcher for {}'.format(path))
        self.path = path
        self.synology_dir = os.path.join(self.path,
                                         '.SynologyWorkingDirectory')
        self.obsolete = False
        self.inotify = inotify.adapters.InotifyTree(self.path)
        self.thread = threading.Thread(target=self.watch, daemon=True)
        self.thread.start()

    def watch(self):
        for event in self.inotify.event_gen(yield_nones=False):
            if self.obsolete:
                logger.info('Exiting obsolete watcher for {}'.format(
                    self.path))
                return
            (_, type_names, path, filename) = event
            if path == self.synology_dir:
                continue
            if 'IN_CREATE' not in type_names:
                continue
            full_path = os.path.join(path, filename)
            try:
                stat_obj = os.stat(full_path, follow_symlinks=False)
            except Exception:
                continue
            if not stat.S_ISREG(stat_obj.st_mode):
                continue
            logger.info('Touching {}'.format(full_path))
            try:
                os.utime(full_path, times=(stat_obj.st_mtime,
                                           stat_obj.st_mtime))
            except Exception as e:
                logger.info('Failed to touch {} ({}), continuing'.format(
                    full_path, e))

    def wait(self):
        self.thread.join()


def find_tasks():
    conn = sqlite3.connect(sys_db_path)
    cursor = conn.cursor()
    cursor.execute('SELECT sync_folder from session_table')
    return list(r[0] for r in cursor)


def watch_tasks():
    watchers = {}
    for path in find_tasks():
        watchers[path] = TaskWatcher(path)
    i = inotify.adapters.Inotify()
    i.add_watch(sys_db_path)
    for event in i.event_gen(yield_nones=False):
        (_, type_names, path, filename) = event
        if 'IN_MODIFY' not in type_names:
            continue
        logger.info('Rescanning tasks.')
        try:
            tasks = find_tasks()
        except Exception as e:
            logger.info('Failed to open {} ({}), continuing without it'.format(
                sys_db_path, e))
            continue
        new_watchers = {}
        for task in tasks:
            if task in watchers:
                new_watchers[task] = watchers.pop(task)
            else:
                new_watchers[task] = TaskWatcher(task)
        for task, watcher in watchers.items():
            logger.info('Telling watcher for {} to exit'.format(task))
            watcher.obsolete = True
        watchers = new_watchers


def maintain_canary(url, stable_interval):
    unstable_interval = 1
    last_problem = ''
    interval = 0
    while True:
        time.sleep(interval)
        interval = stable_interval
        stat_obj = os.stat(sys_db_path)
        delta = int(time.time() - stat_obj.st_mtime)
        if delta > sys_db_max_idle:
            interval = unstable_interval
            if last_problem != 'idle':
                last_problem = 'idle'
                logger.error(f'{sys_db_path} unmodified in {delta}s; '
                             f'not triggering canary')
            continue
        elif last_problem == 'idle':
            last_problem = ''
            logger.info(f'{sys_db_path} modifications resumed; '
                        f'triggering canary')
        try:
            response = requests.get(url, timeout=5)
            response.raise_for_status()
            logger.debug(f'Successfully fetched {url}')
            last_problem = ''
        except Exception as e:
            new_problem = False
            # It's gross to test for this using a string operation like this,
            # but the root cause of the failure is buried so deep in a stack of
            # nested exceptions that doing it this way is less gross than any
            # of the alternatives.
            if 'Temporary failure in name resolution' in str(e) or \
               'Name or service not known' in str(e):
                if last_problem != 'dns':
                    last_problem = 'dns'
                    new_problem = True
                    logger.error(f'DNS failure fetching {url}')
            else:
                if last_problem != 'fetch':
                    last_problem = 'fetch'
                    new_problem = True
                    logger.exception(f'Failed to fetch {url}')
            interval = unstable_interval
            if new_problem:
                logger.error('Sleeping briefly and retrying until success')


def parse_args():
    parser = argparse.ArgumentParser(
        description='Work around Synology Drive data loss bug')
    parser.add_argument('--canary-url', action='store', help='URL to fetch '
                        'periodically as proof of life')
    parser.add_argument('--canary-interval', type=int, action='store',
                        default=300, help='How frequently (seconds) to  fetch '
                        'canary URL (default 300)')
    return parser.parse_args()


def main():
    global logger
    logger = logging.getLogger(os.path.basename(sys.argv[0]))
    logger.setLevel(logging.DEBUG)
    handler = logging.handlers.SysLogHandler(address='/dev/log')
    logger.addHandler(handler)
    args = parse_args()
    if (args.canary_url):
        canary_thread = threading.Thread(
            target=maintain_canary, daemon=True,
            args=(args.canary_url, args.canary_interval))
        canary_thread.start()
    watch_tasks()


if __name__ == '__main__':
    main()
