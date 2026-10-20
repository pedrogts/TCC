from setuptools import setup
from Cython.Build import cythonize

setup(
    name='Radix Core Cython',
    ext_modules=cythonize("radix_core.pyx", compiler_directives={'language_level': "3"})
)
