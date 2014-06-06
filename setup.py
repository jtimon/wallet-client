# -*- coding: utf-8 -*-
# Copyright © 2012-2013, RokuSigma Inc. as an unpublished work.
# Proprietary property and company confidential: all rights reserved.
# See COPYRIGHT for details.

import os

from setuptools import setup, find_packages

here = os.path.abspath(os.path.dirname(__file__))
README = open(os.path.join(here, 'README.md')).read()
CHANGES = open(os.path.join(here, 'CHANGES.md')).read()
requires = filter(lambda r:'libs/' not in r,
    open(os.path.join(here, 'requirements.txt')).read().split())

setup(**{
    'name': 'wallet',
    'version': '1.0.0',
    'description': 'wallet',
    'long_description': README + '\n\n' + CHANGES,
    'classifiers': [
        "Programming Language :: Python",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Internet :: WWW/HTTP :: WSGI :: Application",
    ],
    'author':       'Blockstream.io Inc.',
    'author_email': 'support@blockstream.io',
    'url':          'https://wallet.blockstream.io/',
    'keywords': 'web wsgi',
    'packages': find_packages(),
    'include_package_data': True,
    'zip_safe': False,
    'install_requires': requires,
})
