# Copyright (C) 2014-2018 Apple Inc. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1.  Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
# 2.  Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import os
import stat
import json
from zipfile import ZipFile, BadZipfile
from urllib2 import urlopen, HTTPError, URLError
from webkitpy.common.webkit_finder import WebKitFinder
from webkitpy.port.ios import IOSPort

class BuildBinariesFetcher:
    """A class to which automates the fetching of the build binaries revisions."""

    def __init__(self, host, port_name, architecture, configuration, build_binaries_revision=None):
        """ Initialize the build url options needed to construct paths"""
        self.host = host
        self.port_name = port_name
        self.os_version_name = self._get_os_version_name()
        self.architecture = architecture
        self.configuration = configuration
        self.build_binaries_revision = build_binaries_revision
        self.s3_zip_url = None

        # FIXME find version of this endpoint which returns more than the latest 30 builds
        self.s3_build_binaries_api_base_path = 'https://q1tzqfy48e.execute-api.us-west-2.amazonaws.com/v2/latest'

    @property
    def downloaded_binaries_dir(self):
        webkit_finder = WebKitFinder(self.host.filesystem)
        return webkit_finder.path_from_webkit_base('WebKitBuild', 'downloaded_binaries')

    @property
    def should_default_to_latest_revision(self):
        return self.build_binaries_revision == None

    @property
    def s3_build_type(self):
        return "{self.port_name}-{self.os_version_name}-{self.architecture}-{self.configuration}".format(self=self).lower()

    @property
    def s3_build_binaries_url(self):
        return self.host.filesystem.join(self.s3_build_binaries_api_base_path, self.s3_build_type)

    @property
    def local_build_binaries_dir(self):
        return self.host.filesystem.join(self.downloaded_binaries_dir, self.s3_build_type, self.build_binaries_revision)

    @property
    def local_zip_path(self):
        return "{self.local_build_binaries_dir}.zip".format(self=self)

    @property
    def layout_helper_exec_path(self):
        return self.host.filesystem.join(self.local_build_binaries_dir, self.configuration.capitalize(), 'LayoutTestHelper')

    @property
    def webkit_test_runner_exec_path(self):
        return self.host.filesystem.join(self.local_build_binaries_dir, self.configuration.capitalize(), 'WebKitTestRunner')

    def _get_os_version_name(self):
        if self.port_name == "mac":
            return self.host.platform.os_version_name().lower().replace(' ', '')
        elif self.port_name == "ios-simulator":
            return IOSPort.CURRENT_VERSION.major
        else:
            raise NotImplementedError('Downloading binaries for the %s is not currently supported' % self.port_name)

    def get_path(self):
        # check to see if previously downloaded local version exists before downloading
        if self.host.filesystem.exists(self.local_build_binaries_dir):
            print('Build Binary has already been downloaded and can be found at: %s' % self.local_build_binaries_dir)
            return self.local_build_binaries_dir

        return self._fetch_build_binaries_json()

    def _fetch_build_binaries_json(self):

        response = urlopen(self.s3_build_binaries_url)
        build_binaries_json = json.load(response)

        if build_binaries_json['Count'] >= 1:

            if self.should_default_to_latest_revision:
                print('first %s' % build_binaries_json['Items'][0]['revision']['N'])
                self.s3_zip_url = build_binaries_json['Items'][0]['revision']['N']
            else:
                for item in build_binaries_json['Items']:
                    revision = item['revision']['N']
                    if revision == self.build_binaries_revision:
                        self.s3_zip_url = item['s3_url']['S']
                        break

            if self.s3_zip_url:
                return self._fetch_build_binaries_zip()
            else:
                raise Exception('Could not find revision %s for the constructed API path: %s'
                                    % (self.build_binaries_revision, self.s3_build_binaries_url))
        else:
            raise Exception('No build revisions found at: %s' % self.s3_build_binaries_url)

    def _fetch_build_binaries_zip(self):

        try:
            # attempt to download the zip file
            print("Starting ZipFile Download: %s" % self.s3_zip_url)
            build_zip = urlopen(self.s3_zip_url)

            self.host.filesystem.maybe_make_directory(self.local_build_binaries_dir)

            with open(self.local_zip_path, "wb") as local_build_binaries:
                print("Writing ZipFile To Local Drive: %s" % self.local_zip_path)
                local_build_binaries.write(build_zip.read())

            print("Extracting ZipFile")
            with ZipFile(self.local_zip_path, 'r') as zip_file:
                zip_file.extractall(self.local_build_binaries_dir)

                print ("Deleting ZipFile Extracted Binaries Can Be Found Here: %s" % self.local_build_binaries_dir)
                os.remove(self.local_zip_path)

                self._set_permissions_for_executables()

                return self.local_build_binaries_dir
        except BadZipfile:
            raise Exception('BadZipfile Error: could not exact ZipFile')
        except HTTPError:
            raise Exception('HTTP Error: internet connectivity is required fetch binary file')
        except URLError:
            raise Exception('URLError Error: please make sure %s is a valid link' % self.s3_build_binaries_url)

    def _set_permissions_for_executables(self):

        if self.host.filesystem.exists(self.layout_helper_exec_path):
            os.chmod(self.layout_helper_exec_path, stat.S_IRWXU)

        if self.host.filesystem.exists(self.webkit_test_runner_exec_path):
            os.chmod(self.webkit_test_runner_exec_path, stat.S_IRWXU)