#!/bin/bash

source /home/gitcloud/pyenv311/bin/activate
python /home/gitcloud/scripts/sync-winrm.py
deactivate
