#!/usr/bin/env python3
import os
import json
import glob
import inflection
from datetime import datetime
from collections import OrderedDict

migration_template = """class {} < ActiveRecord::Migration[5.2]
  def self.up
    # add your code here
  end

  def self.down
    # add your code here
  end
end
"""


def load_skeleton():
    t = glob.glob('*.szpm.template')
    if len(t) != 1:
        raise Exception("Cannot find szpm template")
    with open(t[0], 'r', encoding='utf-8') as f:
        skeleton = json.load(f, object_pairs_hook=OrderedDict)
        return skeleton


def main():
    skeleton = load_skeleton()
    name = skeleton["name"].lower()
    raw_name = input("Enter migration name: ")
    migration_base_name = "{}_{}".format(name, inflection.underscore(raw_name))
    migration_name = inflection.camelize(migration_base_name, uppercase_first_letter=True)
    contents = migration_template.format(migration_name)
    time = datetime.utcnow().strftime("%Y%m%d%H%M%S")
    migration_file_name = "{}_{}.rb".format(time, migration_base_name)
    with open(os.path.join("src/db/addon/", skeleton["name"], migration_file_name), 'w') as f:
        f.write(contents)


main()
