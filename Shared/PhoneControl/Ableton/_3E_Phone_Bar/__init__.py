# SPDX-License-Identifier: MIT
from .phone_bar import PhoneBar

def create_instance(c_instance):
    return PhoneBar(c_instance=c_instance)
