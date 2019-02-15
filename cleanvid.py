#!/usr/bin/env python3

import argparse
import errno
import os
import sys
import re
import pysrt
import delegator
from subliminal import *
from babelfish import Language
from caselessdictionary import CaselessDictionary

__location__ = os.path.realpath(os.path.dirname(__file__))

######## GetSubtitles #########################################################
def GetSubtitles(vidFileSpec, srtLanguage):
  subFileSpec = ""

  if os.path.isfile(vidFileSpec):
    subFileParts = os.path.splitext(vidFileSpec)
    subFileSpec = subFileParts[0] + "." + str(Language(srtLanguage)) + ".srt";
    if not os.path.isfile(subFileSpec):
      video = Video.fromname(vidFileSpec)
      bestSubtitles = download_best_subtitles([video], {Language(srtLanguage)})
      savedSub = save_subtitles(video, [bestSubtitles[video][0]])

  if subFileSpec and (not os.path.isfile(subFileSpec)):
    subFileSpec = ""

  return subFileSpec

#################################################################################
class VidCleaner(object):
  inputVidFileSpec = ""
  inputSubsFileSpec = ""
  cleanSubsFileSpec = ""
  outputVidFileSpec = ""
  swearsFileSpec = ""
  swearsMap = CaselessDictionary({})
  muteTimeList = []

  ######## init #################################################################
  def __init__(self, iVidFileSpec, iSubsFileSpec, oVidFileSpec, iSwearsFileSpec):
    if os.path.isfile(iVidFileSpec):
      self.inputVidFileSpec = iVidFileSpec
    else:
      raise IOError(
          errno.ENOENT, os.strerror(errno.ENOENT), iVidFileSpec)

    if os.path.isfile(iSubsFileSpec):
      self.inputSubsFileSpec = iSubsFileSpec

    if os.path.isfile(iSwearsFileSpec):
      self.swearsFileSpec = iSwearsFileSpec
    else:
      raise IOError(
          errno.ENOENT, os.strerror(errno.ENOENT), iSwearsFileSpec)

    self.outputVidFileSpec = oVidFileSpec
    if os.path.isfile(self.outputVidFileSpec):
      os.remove(self.outputVidFileSpec)

  ######## del ##################################################################
  def __del__(self):
    if os.path.isfile(self.cleanSubsFileSpec) and (not os.path.isfile(self.outputVidFileSpec)):
      os.remove(self.cleanSubsFileSpec)

  ######## CreateCleanSubAndMuteList #################################################
  def CreateCleanSubAndMuteList(self):
    subFileParts = os.path.splitext(self.inputSubsFileSpec)
    self.cleanSubsFileSpec = subFileParts[0] + "_clean" + subFileParts[1]

    lines = []

    with open(self.swearsFileSpec) as f:
      lines = [line.rstrip('\n') for line in f]

    for line in lines:
      lineMap = line.split("|")
      if len(lineMap) > 1:
        self.swearsMap[lineMap[0]] = lineMap[1]
      else:
        self.swearsMap[lineMap[0]] = "*****"

    replacer = re.compile(r'\b(' + '|'.join(self.swearsMap.keys()) + r')\b', re.IGNORECASE)

    subs = pysrt.open(self.inputSubsFileSpec)
    newSubs = pysrt.SubRipFile()
    for sub in subs:
      newText = replacer.sub(lambda x: self.swearsMap[x.group()], sub.text)
      if (newText != sub.text):
        newSub = sub
        newSub.text = newText
        newSubs.append(newSub)
    newSubs.save(self.cleanSubsFileSpec)

    newLines = []
    for sub in newSubs:
      newLines.append([sub.start.to_time(), sub.end.to_time()])

    self.muteTimeList = []
    for timePair in newLines:
      lineStart = (timePair[0].hour * 60.0 * 60.0) + (timePair[0].minute * 60.0) + timePair[0].second + (timePair[0].microsecond / 1000000.0)
      lineEnd = (timePair[1].hour * 60.0 * 60.0) + (timePair[1].minute * 60.0) + timePair[1].second + (timePair[1].microsecond / 1000000.0)
      self.muteTimeList.append("volume=enable='between(t," + format(lineStart, '.3f') + "," + format(lineEnd, '.3f') + ")':volume=0")

  ######## MultiplexCleanVideo ###################################################
  def MultiplexCleanVideo(self):
    ffmpegResult = delegator.run("ffmpeg -y -i \"" + self.inputVidFileSpec + "\"" + \
                    " -c:v copy " + \
                    " -af \"" + ",".join(self.muteTimeList) + "\"" \
                    " -c:a aac -ac 2 -ab 224k -ar 44100 \"" + \
                    self.outputVidFileSpec + "\"", block=True)
    if (ffmpegResult.return_code != 0) or (not os.path.isfile(self.outputVidFileSpec)):
      print(ffmpegResult.err)
      raise ValueError('Could not process %s' % (self.inputVidFileSpec))

#################################################################################


#################################################################################
if __name__ == '__main__':
  parser = argparse.ArgumentParser()
  parser.add_argument('-s', '--subs',   help='.srt subtitle file (will attempt auto-download if unspecified)', metavar='<srt>')
  parser.add_argument('-i', '--input',  help='input video file', metavar='<input video>')
  parser.add_argument('-o', '--output', help='output video file', metavar='<output video>')
  parser.add_argument('-w', '--swears', help='text file containing profanity (with optional mapping)', \
                                        default=os.path.join(__location__, 'swears.txt'), \
                                        metavar='<profanity file>')
  parser.add_argument('-l', '--lang',   help='language for srt download (default is "eng")', default='eng', metavar='<language>')
  args = parser.parse_args()

  inFile = args.input
  outFile = args.output
  subsFile = args.subs
  swearsFile = args.swears
  lang = args.lang
  if inFile:
    inFileParts = os.path.splitext(inFile)
    if (not outFile):
      outFile = inFileParts[0] + "_clean" + inFileParts[1]
    if (not subsFile):
      subsFile = GetSubtitles(inFile, lang)

  cleaner = VidCleaner(inFile, subsFile, outFile, swearsFile)
  cleaner.CreateCleanSubAndMuteList()
  cleaner.MultiplexCleanVideo()

#################################################################################
