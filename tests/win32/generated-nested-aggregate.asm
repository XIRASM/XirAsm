import("os/win32/defs/networkmanagement_dhcp.inc")

assert(sizeof(win32_NetworkManagement_Dhcp_DHCP_SUBNET_ELEMENT_UNION32) == 4)
assert(sizeof(win32_NetworkManagement_Dhcp_DHCP_SUBNET_ELEMENT_UNION64) == 8)
assert(sizeof(win32_NetworkManagement_Dhcp_DHCP_SUBNET_ELEMENT_DATA32) == 8)
assert(sizeof(win32_NetworkManagement_Dhcp_DHCP_SUBNET_ELEMENT_DATA64) == 16)
assert(win32_NetworkManagement_Dhcp_DHCP_SUBNET_ELEMENT_DATA_field_Element_offset32 == 4)
assert(win32_NetworkManagement_Dhcp_DHCP_SUBNET_ELEMENT_DATA_field_Element_offset64 == 8)

const element: win32_NetworkManagement_Dhcp_DHCP_SUBNET_ELEMENT_UNION64 = win32_NetworkManagement_Dhcp_DHCP_SUBNET_ELEMENT_UNION64 {
    IpRange: 0
}

emit.struct(element)
