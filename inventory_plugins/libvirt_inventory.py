# GNU General Public License v3.0+ (see COPYING
# or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import libvirt
import logging
import netaddr
import os
import xmltodict

from collections import namedtuple

from ansible.plugins.inventory import (
    BaseInventoryPlugin, Constructable, Cacheable
)
from ansible.inventory.helpers import get_group_vars
from ansible.utils.vars import combine_vars
from ansible.errors import AnsibleError

DOCUMENTATION = '''
    name: openstack
    plugin_type: inventory
    author:
      - Lars Kellogg-Stedman <lars@redhat.com>
    short_description: libvirt inventory source
    requirements:
        - libvirt
    extends_documentation_fragment:
        - inventory_cache
        - constructed
    description:
        - Get inventory hosts from libvirtd
        - Uses libvirt.(yml|yaml) configuration file to configure the
          inventory plugin
    options:
        plugin:
            description: >-
                token that ensures this is a source file for the
                'libvirt' plugin.
            required: True
            choices: ['libvirt']
        uri:
            description: >-
                uri for connecting to libvirt (e.g. 'qemu:///system')
            required: false
        networks:
            description: >-
                only return interface address within one of the
                listed subnets
            required: false
        mechanisms:
            description: >-
                what mechanism to use to get address of libvirt guests.
            required: false
        include_inactive:
            description: >-
                set to true if you want inactive hosts included in
                the inventory.
            required: false
'''

LOG = logging.getLogger(__name__)
MECHANISMS = {
    'agent': libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_AGENT,
    'arp': libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_ARP,
    'lease': libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_LEASE,
}
DEFAULT_MECHANISMS = ['agent', 'lease', 'arp']
METADATA_KEYS = {
    'libvirt_title': libvirt.VIR_DOMAIN_METADATA_TITLE,
    'libvirt_description': libvirt.VIR_DOMAIN_METADATA_DESCRIPTION,
}


class InventoryModule(BaseInventoryPlugin, Constructable, Cacheable):

    NAME = 'libvirt_inventory'

    def verify_file(self, path):

        if super(InventoryModule, self).verify_file(path):
            base, ext = os.path.splitext(path)

            if base.endswith('libvirt') and ext in ('.yaml', '.yml'):
                return True

        return False

    def _connect_to_libvirt(self):
        self._lv_uri = self.get_option('uri')
        LOG.info('connecting to libvirt at %s', self._lv_uri)

        try:
            self._lv = libvirt.open(self._lv_uri)
        except libvirt.libvirtError as err:
            raise AnsibleError('Unable to connect to libvirtd: {}'.format(err))

    def _lookup_dom_address(self, host, dom):
        mechanisms = self.get_option('mechanisms') or DEFAULT_MECHANISMS
        networks = self.get_option('networks') or []
        networks = [netaddr.IPNetwork(net) for net in networks]

        for mech in mechanisms:
            if mech not in MECHANISMS:
                raise AnsibleError('invalid mechanism: {}'.format(mech))

            LOG.debug('looking up %s address using %s mechanism',
                      host,
                      mech)

            # convert mechanism name to numeric constant
            mech = MECHANISMS[mech]

            try:
                interfaces = dom.interfaceAddresses(mech)
            except libvirt.libvirtError:
                continue

            for ifname, ifinfo in interfaces.items():
                if ifname == 'lo':
                    continue

                LOG.debug('examining %s interface %s', host, ifname)

                addresses = ifinfo.get('addrs')
                addresses = [] if addresses is None else addresses

                for addr in addresses:
                    selected = addr['addr']
                    if (not networks) or any(selected in net for net in networks):
                        LOG.debug('found address %s for interface %s',
                                  selected,
                                  ifname)
                        return selected

    def _set_libvirt_vars(self, host, dom):
        data = xmltodict.parse(dom.XMLDesc())

        data['active'] = dom.isActive()
        for k in data['domain']['devices']:
            if not isinstance(data['domain']['devices'][k], list):
                data['domain']['devices'][k] = [
                    data['domain']['devices'][k]
                ]

        self.inventory.set_variable(host, 'libvirt', data['domain'])

    def parse(self, inventory, loader, path, cache=True):

        super(InventoryModule, self).parse(inventory, loader, path)
        self._read_config_data(path)
        self._connect_to_libvirt()
        self.inventory.add_group('libvirt')

        strict = self.get_option('strict')

        for dom in self._lv.listAllDomains():
            host = dom.name()
            LOG.info('inspecting %s', host)

            if not self.get_option('include_inactive') and \
                    dom.state() != libvirt.VIR_DOMAIN_RUNNING:
                LOG.info('skipping %s (not running)', host)
                continue

            self.inventory.add_host(host)
            self.inventory.add_child('libvirt', host)

            address = self._lookup_dom_address(host, dom)
            if address is None:
                LOG.warning('failed to find address for %s', host)
            else:
                self.inventory.set_variable(host, 'ansible_host', address)

            self._set_libvirt_vars(host, dom)

            hostvars = combine_vars(
                get_group_vars(
                    inventory.hosts[host].get_groups()),
                inventory.hosts[host].get_vars())

            # create composite vars
            self._set_composite_vars(self.get_option('compose'),
                                     hostvars,
                                     host,
                                     strict=strict
                                     )
            # constructed groups based on conditionals
            self._add_host_to_composed_groups(self.get_option('groups'),
                                              hostvars,
                                              host,
                                              strict=strict)

            # constructed groups based variable values
            self._add_host_to_keyed_groups(self.get_option('keyed_groups'),
                                           hostvars,
                                           host,
                                           strict=strict)


libvirt_error = namedtuple('libvirt_error', [
    'code', 'domain', 'message', 'level', 's1', 's2', 's3', 'i1', 'i2'
])


def libvirt_error_handler(ctx, err):
    err = libvirt_error(*err)
    LOG.info('libvirt: %s', err.message)


libvirt.registerErrorHandler(libvirt_error_handler, None)
