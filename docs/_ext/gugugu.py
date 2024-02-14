from functools import partial
from docutils.nodes import reference, literal
from sphinx.config import Config


def gugugu_source_role(name, rawtext, text, lineno, inliner, options=None,
                       content=None, *, config):

    if options is None:
        options = dict()
    get_source_link = config.gugugu_get_source_link
    if get_source_link is None:
        node = literal(rawtext, text, **options)
    else:
        link = get_source_link(text)
        node = reference(
            rawsource=rawtext, text=text, refuri=link, **options)
    return [node], []


def setup(app):
    app.add_config_value("gugugu_get_source_link", None, "env")
    app.add_role("gugugu-source", partial(gugugu_source_role, config=app.config))

    return {}
