class CaselessDictionary(dict):
    """Dictionary that enables case insensitive searching while preserving case sensitivity
when keys are listed, ie, via keys() or items() methods.

Works by storing a lowercase version of the key as the new key and stores the original key-value
pair as the key's value (values become dictionaries)."""

    def __init__(self, initval={}):
        if isinstance(initval, dict):
            for key, value in initval.items():
                self.__setitem__(key, value)
        elif isinstance(initval, list):
            for (key, value) in initval:
                self.__setitem__(key, value)

    def __repr__(self):
        ans = dict()
        for key, val in self.items():
            ans[key] = val
        return str(ans)

    # __str__ for print()
    def __str__(self):
        return self.__repr__()

    def __contains__(self, key):
        return dict.__contains__(self, key.lower())

    def __getitem__(self, key):
        return dict.__getitem__(self, key.lower())['val']

    def __setitem__(self, key, value):
        try:
            return dict.__setitem__(self, key.lower(), {'key': key, 'val': value})
        except AttributeError:
            return dict.__setitem__(self, key, {'key': key, 'val': value})

    def get(self, key, default=None):
        try:
            return dict.__getitem__(self, str(key).lower())['val']
        except KeyError:
            return default

    def has_key(self, key):
        if self.get(key):
            return True
        else:
            return False

    def items(self):
        for v in dict.values(self):
            yield (v['key'], v['val'])

    def keys(self):
        for v in dict.values(self):
            yield v['key']

    def values(self):
        for v in dict.values(self):
            yield v['val']

    def printable(self, sep=', ', key=None):
        if key is None:
            key = self.keys
        try:
            return sep.join(key())
        except TypeError:
            ans = ''
            for v in key():
                ans += str(v)
                ans += sep
            return ans[:-len(sep)]
