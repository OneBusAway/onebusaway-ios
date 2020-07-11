#!/bin/bash

protoc --swift_out=. --swift_opt=Visibility=Public OBAKitCore/Models/Protobuf/gtfs-realtime.proto