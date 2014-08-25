# Copyright (c) 2013 Cloudbase Solutions Srl
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import comtypes
import ctypes

from comtypes import client
from ctypes import wintypes

CLSID_VdsLoader = '{9C38ED61-D565-4728-AEEE-C80952F0ECDE}'

VDS_SP_UNKNOWN= 0
VDS_SP_ONLINE	= 0x1
VDS_SP_OFFLINE_SHARED = 0x2
VDS_SP_OFFLINE = 0x3
VDS_SP_OFFLINE_INTERNAL	= 0x4
VDS_SP_MAX	= 0x5


class IEnumVdsObject(comtypes.IUnknown):
    _iid_ = comtypes.GUID("{118610b7-8d94-4030-b5b8-500889788e4e}")

    _methods_ = [
        comtypes.COMMETHOD([], comtypes.HRESULT, 'Next',
                           (['in'], wintypes.ULONG, 'celt'),
                           (['out'], ctypes.POINTER(ctypes.POINTER(
                                                    comtypes.IUnknown)),
                            'ppObjectArray'),
                           (['out'], ctypes.POINTER(wintypes.ULONG),
                            'pcFetched')),
    ]


class IVdsServiceSAN(comtypes.IUnknown):
    _iid_ = comtypes.GUID("{fc5d23e8-a88b-41a5-8de0-2d2f73c5a630}")

    _methods_ = [
        comtypes.COMMETHOD([], comtypes.HRESULT, 'GetSANPolicy',
            (['out'], ctypes.POINTER(ctypes.c_uint), 'pSanPolicy')),
        comtypes.COMMETHOD([], comtypes.HRESULT, 'SetSANPolicy',
            (['in'], ctypes.c_uint, 'SanPolicy')),
    ]


class IVdsService(comtypes.IUnknown):
    _iid_ = comtypes.GUID("{0818a8ef-9ba9-40d8-a6f9-e22833cc771e}")

    _methods_ = [
        comtypes.COMMETHOD([], comtypes.HRESULT, 'IsServiceReady'),
        comtypes.COMMETHOD([], comtypes.HRESULT, 'WaitForServiceReady'),
        comtypes.COMMETHOD([], comtypes.HRESULT, 'GetProperties',
                           (['out'], ctypes.c_void_p, 'pServiceProp')),
        comtypes.COMMETHOD([], comtypes.HRESULT, 'QueryProviders',
                           (['in'], wintypes.DWORD, 'masks'),
                           (['out'],
                            ctypes.POINTER(ctypes.POINTER(IEnumVdsObject)),
                            'ppEnum'))
    ]


class IVdsServiceLoader(comtypes.IUnknown):
    _iid_ = comtypes.GUID("{e0393303-90d4-4a97-ab71-e9b671ee2729}")

    _methods_ = [
        comtypes.COMMETHOD([], comtypes.HRESULT, 'LoadService',
                           (['in'], wintypes.LPCWSTR, 'pwszMachineName'),
                           (['out'],
                            ctypes.POINTER(ctypes.POINTER(IVdsService)),
                            'ppService'))
    ]


def check_san_offline_policy():
    loader = client.CreateObject(CLSID_VdsLoader, interface=IVdsServiceLoader)
    svc = loader.LoadService(None)
    svc.WaitForServiceReady()

    svc_san = svc.QueryInterface(IVdsServiceSAN)

    curr_policy = svc_san.GetSANPolicy()
    print "Current SAN policy: %s" % curr_policy

    if curr_policy not in [VDS_SP_OFFLINE, VDS_SP_OFFLINE_SHARED]:
        print "Setting  SAN policy: VDS_SP_OFFLINE"
        svc_san.SetSANPolicy(VDS_SP_OFFLINE)
        return True


if __name__ == "__main__":
    if check_san_offline_policy():
        exit(1)
