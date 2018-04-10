# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Import pip requirements into Bazel."""

def expand_deps(d):
    return "\n".join(["{} {}".format(k, " ".join([v for v in vv])) for k, vv in d.items()])

def expand_deps_to_dict(d):
    return "".join(['\n    "{}": [{}],'.format(k, ", ".join(['"{}"'.format(v) for v in vv])) for k, vv in d.items()])

def _pip_import_impl(repository_ctx):
  """Core implementation of pip_import."""

  # Add an empty top-level BUILD file.
  # This is because Bazel requires BUILD files along all paths accessed
  # via //this/sort/of:path and we wouldn't be able to load our generated
  # requirements.bzl without it.
  repository_ctx.file("BUILD", """
package(default_visibility = ["//visibility:public"])
py_library(
    name = "site",
    srcs = [":sitecustomize.py"],
    imports = ["."],
)
sh_binary(
    name = "update",
    srcs = ["update.sh"],
)
""")

  repository_ctx.file("python/BUILD", "")
  print(repository_ctx.attr.additional_runtime_deps)
  repository_ctx.file("runtime-fix.txt", expand_deps(repository_ctx.attr.additional_runtime_deps))
  repository_ctx.file("buildtime-fix.txt", expand_deps(repository_ctx.attr.additional_buildtime_deps))
  repository_ctx.template(
    "python/whl.bzl",
    Label("//rules_python:whl.bzl.tpl"),
    substitutions = {
      "%{repo}": repository_ctx.name,
      "%{pip_args}": ", ".join(["\"%s\"" % arg for arg in repository_ctx.attr.pip_args]),
      "%{requirements}": str(repository_ctx.attr.requirements_bzl),
      "%{additional_buildtime_deps}": expand_deps_to_dict(repository_ctx.attr.additional_buildtime_deps),
      "%{additional_runtime_deps}": expand_deps_to_dict(repository_ctx.attr.additional_runtime_deps),
    })

  repository_ctx.template(
    "sitecustomize.py",
    Label("//rules_python:sitecustomize.py.tpl"),
    substitutions = {
      "%{modules}": "".join(["\n    '%s'," % n for n in repository_ctx.attr.alias_namespaces]),
    },
  )

  repository_ctx.template(
    "update.sh",
    Label("//rules_python:update.sh.tpl"),
    substitutions = {
      "%{piptool}": str(repository_ctx.path(repository_ctx.attr._script)),
      "%{name}": repository_ctx.attr.name,
      "%{requirements_txt}": str(repository_ctx.path(repository_ctx.attr.requirements)),
      "%{requirements_bzl}": str(repository_ctx.path(repository_ctx.attr.requirements_bzl)) if repository_ctx.attr.requirements_bzl else "",
      "%{runtime_fix}": str(repository_ctx.path("runtime-fix.txt")),
      "%{buildtime_fix}": str(repository_ctx.path("buildtime-fix.txt")),
      "%{directory}": str(repository_ctx.path("")),
      "%{pip_args}": " ".join(["\"%s\"" % arg for arg in repository_ctx.attr.pip_args]),
    },
    executable=True,
  )

  if repository_ctx.attr.requirements_bzl:
    repository_ctx.symlink(repository_ctx.path(repository_ctx.attr.requirements_bzl), "requirements.bzl")
  else:
    # To see the output, pass: quiet=False
    cmd = [
        "python", repository_ctx.path(repository_ctx.attr._script), "resolve",
        "--name", repository_ctx.attr.name,
        "--input", repository_ctx.path(repository_ctx.attr.requirements),
        "--output", repository_ctx.path("requirements.bzl"),
        "--directory", repository_ctx.path(""),
    ]
    if repository_ctx.attr.requirements_fix:
        cmd += ["--input-fix", repository_ctx.path(repository_ctx.attr.requirements_fix)]
    cmd += ["--"] + repository_ctx.attr.pip_args
    result = repository_ctx.execute(cmd, quiet=False)

    if result.return_code:
        fail("pip_import failed: %s (%s)" % (result.stdout, result.stderr))

pip_import = repository_rule(
    attrs = {
        "requirements": attr.label(
            allow_files = True,
            mandatory = True,
            single_file = True,
        ),
        "requirements_fix": attr.label(
            allow_files = True,
            mandatory = False,
            single_file = True,
        ),
        "requirements_bzl": attr.label(
            allow_files = True,
            single_file = True,
        ),
        "pip_args": attr.string_list(),
        "additional_buildtime_deps": attr.string_list_dict(),
        "additional_runtime_deps": attr.string_list_dict(),
        "alias_namespaces": attr.string_list(default=["google"]),
        "_script": attr.label(
            executable = True,
            default = Label("//tools:piptool.par"),
            cfg = "host",
        ),
    },
    implementation = _pip_import_impl,
)

"""A rule for importing <code>requirements.txt</code> dependencies into Bazel.

This rule imports a <code>requirements.txt</code> file and generates a new
<code>requirements.bzl</code> file.  This is used via the <code>WORKSPACE</code>
pattern:
<pre><code>pip_import(
    name = "foo",
    requirements = ":requirements.txt",
)
load("@foo//:requirements.bzl", "pip_install")
pip_install()
</code></pre>

You can then reference imported dependencies from your <code>BUILD</code>
file with:
<pre><code>load("@foo//:requirements.bzl", "requirement")
py_library(
    name = "bar",
    ...
    deps = [
       "//my/other:dep",
       requirement("futures"),
       requirement("mock"),
    ],
)
</code></pre>

Or alternatively:
<pre><code>load("@foo//:requirements.bzl", "all_requirements")
py_binary(
    name = "baz",
    ...
    deps = [
       ":foo",
    ] + all_requirements,
)
</code></pre>

Args:
  requirements: The label of a requirements.txt file.
"""

def pip_repositories():
  """Pull in dependencies needed for pulling in pip dependencies.

  A placeholder method that will eventually pull in any dependencies
  needed to install pip dependencies.
  """
  pass
