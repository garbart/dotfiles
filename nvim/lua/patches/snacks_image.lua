-- Fixes for reopening images in snacks.image, applied on top of the snacks
-- version pinned in nvim-pack-lock.json. They mirror two open upstream PRs;
-- delete this file once snacks ships them:
--   https://github.com/folke/snacks.nvim/pull/2964
--   https://github.com/folke/snacks.nvim/pull/2918
--
-- Without them an image only shows the first time it is opened in a session.
-- Opening it again leaves a blank buffer or a stuck "identify loading …".

local Image = require('snacks.image.image')
local Placement = require('snacks.image.placement')
local terminal = require('snacks.image.terminal')
local ns = vim.api.nvim_create_namespace('snacks.image')

-- Ghostty and kitty free an image once its last placement is deleted, but
-- snacks still treats it as sent and never transmits it again. Free it
-- explicitly and mark it unsent, so the next placement sends the data anew.
local del = Image.del
function Image:del(pid)
  del(self, pid)
  if not next(self.placements) then
    terminal.request({ a = 'd', d = 'I', i = self.id })
    self.sent = false
  end
end

-- A buffer that leaves its last window is marked hidden and stays hidden
-- after it comes back. Unhide it as soon as a window shows it again. Inline
-- images are hidden and shown by snacks.image.inline, so leave them alone.
local update = Placement.update
function Placement:update()
  if self.hidden and not self.opts.inline and #self:wins() > 0 then
    self.hidden = false
  end
  return update(self)
end

-- Upstream's spinner, except that its timer also stops once the placement is
-- closed (it used to run forever and keep redrawing "loading" over the
-- reopened image), and when it stops it removes the spinner and clears the
-- `modified` flag that emptying the buffer had set: otherwise the image tab
-- shows ● and closing it asks to save. Image buffers can't be edited or
-- written anyway.
function Placement:progress()
  if self.opts.inline or self:ready() then
    return
  end
  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, {})
  vim.bo[self.buf].modifiable = false
  local timer = assert(vim.uv.new_timer())
  local eid ---@type integer?
  timer:start(
    0,
    80,
    vim.schedule_wrap(function()
      local valid = vim.api.nvim_buf_is_valid(self.buf)
      if self.closed or self:ready() or self.img:failed() or not valid then
        timer:stop()
        if not timer:is_closing() then
          timer:close()
        end
        if valid then
          if eid then
            pcall(vim.api.nvim_buf_del_extmark, self.buf, ns, eid)
          end
          vim.bo[self.buf].modified = false
        end
        return
      end
      vim.api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
      eid = vim.api.nvim_buf_set_extmark(self.buf, ns, 0, 0, {
        virt_text = {
          { Snacks.util.spinner(), 'SnacksImageSpinner' },
          { ' ' },
          { self.img._convert:current().name .. ' loading …', 'SnacksImageLoading' },
        },
      })
    end)
  )
end
