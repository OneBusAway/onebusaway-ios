#!/bin/bash

protoc --swift_out=. --swift_opt=Visibility=Public gtfs-realtime.proto