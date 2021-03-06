# Description:
#   http listener for github action payload
#
# Dependencies:
#
# Configuration:
#   HUBOT_MATTERMOST_CHANNEL
#
# Commands:
#
# Notes:
#   expects GITHUB_EVENT_PATH payload from github actions
#   param to signal which environment
#   example with param: curl -X POST -H "Content-Type: application/json" -H "apikey: ${{ secrets.BOT_KEY }}" -d @$GITHUB_EVENT_PATH https://${{ secrets.BOT_URL }}/hubot/github/dev
#
# Author:
#   craigrigdon

matRoom = process.env.HUBOT_MATTERMOST_CHANNEL
configPath = process.env.HUBOT_CONFIG_PATH
route = '/hubot/github/:envkey'

#---------------Supporting Functions-------------------

getTimeStamp = ->
  date = new Date()
  timeStamp = date.getFullYear() + "/" + (date.getMonth() + 1) + "/" + date.getDate() + " " + date.getHours() + ":" +  date.getMinutes() + ":" + date.getSeconds()
  RE_findSingleDigits = /\b(\d)\b/g
  # Places a `0` in front of single digit numbers.
  timeStamp = timeStamp.replace( RE_findSingleDigits, "0$1" )

#----------------Robot-------------------------------

module.exports = (robot) ->

  robot.router.post route, (req, res) ->

    console.log route
    console.log "Called http-listeners-github script"
    # param
    envKey = req.params.envkey ? null
    console.log envKey

    try
      data = if req.body.payload? then JSON.parse req.body.payload else req.body
      console.log data

      # check payload and param exist then send status back to source.
      if envKey == null || data == null
        status = "Expecting <path/(dev|test|prod)> with github event payload"
        console.log status
      else
        status = "Success"
        console.log status

      # check and continue
      if status == "Success"

        # define var from gitHub push payload
        id = data.head_commit.id
        repoFullName = data.repository.full_name
        repoURL = data.repository.html_url
        repo = data.repository.name
        user = data.repository.owner.name
        base = data.repository.master_branch
        ref = data.ref
        branch = ref.split("/").pop()

         # define var from gitHub pr payload
  #      id = data.pull_request.id
  #      repoFullName = data.repository.full_name
  #      repoURL = data.repository.html_url
  #      repo = data.repository.name
  #      user = data.repository.owner.login
  #      base = "master"
  #      ref = data.pull_request.base.ref
  #      branch = ref.split("/").pop()
  #      pullSha = data.pull_request.base.sha
  #      pullNumber = data.number

        console.log "Checking #{id} on #{branch} for #{repoFullName} "

        #TODO ADD APP Block to stop duplicate bot calls.
        # app is locked until pipe is completed or pull sha matches to continue
        # add logic outside to be called by all routes and responders.

        event = robot.brain.get(repoFullName)
        if event
          eventStatus = event.status
          eventPullSha = event.pullSha
        else
          eventStatus = null
          eventPullSha = null

        if not event || eventStatus == "completed"
          # create entry in Brain
          robot.brain.set("#{repoFullName}": {
            commit: id,
            status: null,
            pullSha: null,
            pullNumber: null,
            repoFullName: repoFullName,
            repo: repo,
            user: user,
            branch : branch,
            base: base,
            env: envKey,
            entry: [],
            stage: {
              dev: {deploy_uid: null, deploy_status: null, postdeploy_status: null, jenkins_job: null, test_status: null, promote: false},
              test: {deploy_uid: null, deploy_status: null, postdeploy_status: null, jenkins_job: null, test_status: null, promote: false},
              stage: {deploy_uid: null, deploy_status: null, postdeploy_status: null, jenkins_job: null, test_status: null, promote: false},
              prod: {deploy_uid: null, deploy_status: null, postdeploy_status: null, jenkins_job: null, test_status: null, promote: false}
              }
            })
          console.log "Created new event in Brain"
        else
          console.log "Event Found in  Brain"


        event = robot.brain.get(repoFullName)
        console.log "Event Found in  Brain"
        console.log "Event Exist in Brain: #{JSON.stringify(event)}"


        #TODO: this logic is for demo only will require updated logic.
        #check if pipeline is pending OR there is a pull request pending
        if event.status != "pending" || event.pullSha != null
          # continue on with logic
          event = robot.brain.get(repoFullName)
          console.log "Hubot Brain Has: #{JSON.stringify(event)}"

          # get config file from repo for pipeline mappings
          robot.http(configPath)
           .header('Accept', 'application/json')
           .get() (err, httpres, body2) ->

           # check for errs
             if err
              console.log "Encountered an error fetching config file :( #{err}"
              body2 =  process.env.HUBOT_PIPELINE_MAP ? null  # hardcode for local testing only to be removed

             pipes = JSON.parse(body2)
             console.log pipes

             buildObj = null
             deployObj = null
             exhasted = false

             # check if repo is in config file
             results = pipes.pipelines.where repo: "#{repoFullName}"
             console.log results
             # process first result only
             pipe = results[0]

             if pipe?
              console.log "Repo found in conifg map: #{JSON.stringify(pipe.repo)}"

              #get event from brain
              event = robot.brain.get(repoFullName)

              switch envKey
                when "dev"
                  console.log "define vars for dev"
                  console.log "#{JSON.stringify(pipe.dev)}"
                  buildObj = pipe.dev.build
                  deployObj = pipe.dev.deploy
                  envObj = pipe.dev # may use this later
                  # get Stage object from brain
                  eventStage = event.stage.dev

                when "test"
                  console.log "define vars for test"
                  console.log "#{JSON.stringify(pipe.test)}"
                  buildObj = pipe.test.build
                  deployObj = pipe.test.deploy
                  envObj = pipe.test # may use this later
                  # get Stage object from brain
                  eventStage = event.stage.test

                when "stage"
                  console.log "define vars for stage"
                  console.log "#{JSON.stringify(pipe.stage)}"
                  buildObj = pipe.stage.build
                  deployObj = pipe.stage.deploy
                  envObj = pipe.stage # may use this later
                  # get Stage object from brain
                  eventStage = event.stage.stage

                else
                  mesg = "Pipeline has been exhasted"
                  console.log mesg
                  exhasted = true


             console.log "#{JSON.stringify(buildObj)}"
             console.log "#{JSON.stringify(deployObj)}"
             console.log "#{JSON.stringify(eventStage)}"

             if exhasted == false

               # message
               mesg = "Recieved Github Event [#{id}] on [#{repoFullName}](#{repoURL})"
               console.log mesg

               # update brain
               event = robot.brain.get(repoFullName)
               event.entry.push mesg
               console.log "#{JSON.stringify(event)}"
               event.status = 'pending'

               # send message to chat
               robot.messageRoom matRoom, "#{mesg}"

               #Checking if Jenkins Job else send to OCP to build and deploy
               if buildObj.jenkinsjob
                 # sent to jenkins script
                 robot.emit "jenkins-job", {
                     job      : buildObj.jenkinsjob, # jenkins job name
                     build    : buildObj, #build object from config file
                     deploy   : deployObj, #deploy object from config file
                     repoFullName    : event.repoFullName #repo name from github payload
                     eventStage : eventStage #stage object from memory to update
                     envKey : envKey #environment key
                 }
               else
                 # sent to build deploy script for OCP
                 robot.emit "build-deploy-stage", {
                     build    : buildObj, #build object from config file
                     deploy   : deployObj, #deploy object from config file
                     repoFullName    : event.repoFullName, #repo name from github payload
                     eventStage : eventStage, #stage object from memory to update
                     envKey : envKey, #environment key
                 }

               # send source status
               res.send status

             else
               mesg = "Pipeline has been exhasted for #{repoFullName}"
               console.log mesg

               # message room
               robot.messageRoom matRoom, "#{mesg}"

               # update brain
               event = robot.brain.get(repoFullName)
               event.entry.push mesg
               console.log "#{JSON.stringify(event)}"
               event.status = 'completed'
        else
          # source failed to pass required param and payload
          mesg = "Pipeline is in Progress. Hubot will Not Start new Pipeline"
          console.log mesg

          # send mesg to chat room
          robot.messageRoom matRoom, "#{mesg}"

          # send status back to source with results
          status = mesg
          res.send status

      else
        # source failed to pass required param and payload
        mesg = "Hubot will Not Start new Pipeline Source Failed to pass requred param and payload"
        console.log mesg

        # send mesg to chat room
        robot.messageRoom matRoom, "#{mesg}"

        # send status back to source with results
        status = mesg
        res.send status
    catch err
      console.log err

      mesg = "Error: See Pipeline-bot Logs in OCP. Have a Great Day!"
       # send message to chat
      robot.messageRoom matRoom, mesg
