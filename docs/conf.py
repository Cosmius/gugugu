# Configuration file for the Sphinx documentation builder.
#
# This file only contains a selection of the most common options. For a full
# list see the documentation:
# http://www.sphinx-doc.org/en/master/config

# -- Path setup --------------------------------------------------------------

# If extensions (or modules to document with autodoc) are in another directory,
# add these directories to sys.path here. If the directory is relative to the
# documentation root, use os.path.abspath to make it absolute, like shown here.
#
import os
import sys
sys.path.append(os.path.abspath("./_ext"))
import yaml
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent

with (PROJECT_ROOT / "hpack-common.yaml").open("rt") as h:
    hpack_common = yaml.safe_load(h)[0]


# -- Project information -----------------------------------------------------

project = "Gugugu"
copyright = "2019, Cosmia Fu"
author = "Cosmia Fu"

# The full version, including alpha/beta/rc tags
release = hpack_common["version"]


# -- General configuration ---------------------------------------------------

# Add any Sphinx extension module names here, as strings. They can be
# extensions coming with Sphinx (named "sphinx.ext.*") or your custom
# ones.
extensions = [
    "gugugu",
]

# Add any paths that contain templates here, relative to this directory.
templates_path = ["_templates"]

# List of patterns, relative to source directory, that match files and
# directories to ignore when looking for source files.
# This pattern also affects html_static_path and html_extra_path.
exclude_patterns = ["_build", "Thumbs.db", ".DS_Store"]


# -- Options for HTML output -------------------------------------------------

# The theme to use for HTML and HTML Help pages.  See the documentation for
# a list of builtin themes.
#
html_theme = "alabaster"

# Add any paths that contain custom static files (such as style sheets) here,
# relative to this directory. They are copied after the builtin static files,
# so a file named "default.css" will overwrite the builtin "default.css".
html_static_path = ["_static"]

html_theme_options = {
    "description": f"{release}",
    "extra_nav_links": {
        "Source at GitHub": "https://github.com/Cosmius/gugugu",
        "Prebuilt binaries": "https://github.com/Cosmius/gugugu/releases",
    },
}


def gugugu_get_source_link(path: str):
    rv = f"https://github.com/Cosmius/gugugu/blob/master/{path}"
    return rv.rstrip("/")
