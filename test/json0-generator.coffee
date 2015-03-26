json0 = require '../lib/json0'
{randomInt, randomReal, randomWord} = require 'ot-fuzzer'

# This is an awful function to clone a document snapshot for use by the random
# op generator. .. Since we don't want to corrupt the original object with
# the changes the op generator will make.
clone = (o) -> JSON.parse(JSON.stringify(o))

randomKey = (obj) ->
  if Array.isArray(obj)
    if obj.length == 0
      undefined
    else
      randomInt obj.length
  else
    count = 0

    for key of obj
      result = key if randomReal() < 1/++count
    result

# Generate a random new key for a value in obj.
# obj must be an Object.
randomNewKey = (obj) ->
  # There's no do-while loop in coffeescript.
  key = randomWord()
  key = randomWord() while obj[key] != undefined
  key

# Generate a random object
randomThing = ->
  switch randomInt 6
    when 0 then null
    when 1 then ''
    when 2 then randomWord()
    when 3
      obj = {}
      obj[randomNewKey(obj)] = randomThing() for [1..randomInt(5)]
      obj
    when 4 then (randomThing() for [1..randomInt(5)])
    when 5 then randomInt(50)

# Pick a random path to something in the object.
randomPath = (data) ->
  path = []

  while randomReal() > 0.85 and typeof data == 'object'
    key = randomKey data
    break unless key?

    path.push key
    data = data[key]

  path
  
randomArrayPath = (data, excludePath) ->
  # loop through the whole doc and find paths to arrays
  arrays = []
  
  queue = [[data,[],0,true]]
  while queue.length > 0
    [obj,path,depth,common] = queue.splice(0, 1)[0]
    if Array.isArray(obj)
      # save array
      arrays.push(path)
      for p, key in obj
          newPath = path[..]
          newPath.push(key)
          # don't descend into children of excludePath
          queue.push([p, newPath, depth+1, (common and excludePath[depth] == key)])
    else if (typeof obj == 'object')
      # pass through objects
      for key,p of obj
        newPath = path[..]
        newPath.push(key)
        queue.push([p, newPath, depth+1, (common and excludePath[depth] == key)])
  
  # randomly select one of the arrays
  path = arrays[randomInt(arrays.length-1)]
  # navigate path
  operand = data
  for p in path
    operand = operand[p]
  # choose a random position in the array
  path.push(randomInt operand.length)
  path


module.exports = genRandomOp = (data) ->
  pct = 0.95

  container = data: clone data

  op = while randomReal() < pct
    pct *= 0.6

    # Pick a random object in the document operate on.
    path = randomPath(container['data'])

    # parent = the container for the operand. parent[key] contains the operand.
    parent = container
    key = 'data'
    for p in path
      parent = parent[key]
      key = p
    operand = parent[key]

    if randomReal() < 0.4 and parent != container and Array.isArray(parent)
      # List move
      
      # Remove the element from its current position in the list
      #console.log(JSON.stringify(container,null,2))
      #console.log(path)
      parent.splice key, 1
      
      newPath = randomArrayPath(container['data'], path)
      
      #console.log(newPath)

      newParent = container
      newKey = 'data'
      for p in newPath
        newParent = newParent[newKey]
        newKey = p
      
      if newParent == parent
        parent.splice newKey, 0, operand
        # insert it in the same array
        #console.log({p:path, lm:newKey})
        {p:path, lm:newKey}
      else
        # insert it in the new array
        newParent.splice newKey, 0, operand
        #console.log({p:path, lm:newPath})
        {p:path, lm:newPath}

    else if randomReal() < 0.3 or operand == null
      # Replace

      newValue = randomThing()
      parent[key] = newValue

      if Array.isArray(parent)
        {p:path, ld:operand, li:clone(newValue)}
      else
        {p:path, od:operand, oi:clone(newValue)}

    else if typeof operand == 'string'
      # String. This code is adapted from the text op generator.

      if randomReal() > 0.5 or operand.length == 0
        # Insert
        pos = randomInt(operand.length + 1)
        str = randomWord() + ' '

        path.push pos
        parent[key] = operand[...pos] + str + operand[pos..]
        c = {p:path, si:str}
      else
        # Delete
        pos = randomInt(operand.length)
        length = Math.min(randomInt(4), operand.length - pos)
        str = operand[pos...(pos + length)]

        path.push pos
        parent[key] = operand[...pos] + operand[pos + length..]
        c = {p:path, sd:str}

      if json0._testStringSubtype
        # Subtype
        subOp = {p:path.pop()}
        if c.si?
          subOp.i = c.si
        else
          subOp.d = c.sd

        c = {p:path, t:'text0', o:[subOp]}

      c

    else if typeof operand == 'number'
      # Number
      inc = randomInt(10) - 3
      parent[key] += inc
      {p:path, na:inc}

    else if Array.isArray(operand)
      # Array. Replace is covered above, so we'll just randomly insert or delete.
      # This code looks remarkably similar to string insert, above.

      if randomReal() > 0.5 or operand.length == 0
        # Insert
        pos = randomInt(operand.length + 1)
        obj = randomThing()

        path.push pos
        operand.splice pos, 0, obj
        {p:path, li:clone(obj)}
      else
        # Delete
        pos = randomInt operand.length
        obj = operand[pos]

        path.push pos
        operand.splice pos, 1
        {p:path, ld:clone(obj)}
    else
      # Object
      k = randomKey(operand)

      if randomReal() > 0.5 or not k?
        # Insert
        k = randomNewKey(operand)
        obj = randomThing()

        path.push k
        operand[k] = obj
        {p:path, oi:clone(obj)}
      else
        obj = operand[k]

        path.push k
        delete operand[k]
        {p:path, od:clone(obj)}

  [op, container.data]
